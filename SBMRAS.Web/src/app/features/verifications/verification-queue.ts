import { ChangeDetectionStrategy, Component, DestroyRef, OnInit, computed, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { DatePipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { MatButtonModule } from '@angular/material/button';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatIconModule } from '@angular/material/icon';
import { MatPaginatorModule, PageEvent } from '@angular/material/paginator';
import { MatSelectModule } from '@angular/material/select';
import { MatTooltipModule } from '@angular/material/tooltip';

import { ViewState } from '../../core/models/api.models';
import { ImportFacilityOption } from '../../core/models/imports.models';
import { Permissions } from '../../core/models/permissions';
import { ChangeDecision, InventoryChange } from '../../core/models/verification.models';
import { ImportsService } from '../../core/services/imports.service';
import { SessionService } from '../../core/services/session.service';
import { UiService } from '../../core/services/ui.service';
import { VerificationService } from '../../core/services/verification.service';
import { ApiError, errorMessage } from '../../core/utils/api-error';
import { PageHeader } from '../../shared/components/page-header';
import { StatePanel } from '../../shared/components/state-panel';

interface ValueDiff {
  label: string;
  before: string;
  after: string;
  delta: string | null;
  changed: boolean;
}

const FLAG_INFO: Record<string, { label: string; hint: string; icon: string }> = {
  LARGE_JUMP: { label: 'Large jump', hint: 'Change exceeds the configured jump threshold', icon: 'trending_up' },
  DUPLICATE: { label: 'Duplicate', hint: 'Identical submission received recently', icon: 'content_copy' },
  NEGATIVE: { label: 'Negative', hint: 'Negative quantity submitted', icon: 'remove_circle' },
  CONFLICT: { label: 'Conflict', hint: 'Conflicts with another pending submission', icon: 'sync_problem' },
  STALE: { label: 'Stale', hint: 'Record past its validity window', icon: 'schedule' },
  MISSING_FIELD: { label: 'Missing field', hint: 'Required value missing', icon: 'help' },
  EXPIRING: { label: 'Expiring', hint: 'Units close to expiry', icon: 'hourglass_bottom' },
};

@Component({
  selector: 'sb-verification-queue',
  imports: [
    DatePipe,
    FormsModule,
    MatButtonModule,
    MatFormFieldModule,
    MatIconModule,
    MatPaginatorModule,
    MatSelectModule,
    MatTooltipModule,
    PageHeader,
    StatePanel,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './verification-queue.html',
  styleUrl: './verification-queue.scss',
})
export class VerificationQueue implements OnInit {
  private readonly changes = inject(VerificationService);
  private readonly imports = inject(ImportsService);
  private readonly session = inject(SessionService);
  private readonly ui = inject(UiService);
  private readonly destroyRef = inject(DestroyRef);

  protected readonly state = signal<ViewState>('loading');
  protected readonly error = signal('');
  protected readonly items = signal<InventoryChange[]>([]);
  protected readonly total = signal(0);
  protected readonly facilities = signal<ImportFacilityOption[]>([]);
  protected readonly busyId = signal<number | null>(null);
  protected readonly canVerify = computed(() => this.session.hasPermission(Permissions.InventoryVerify));

  protected status: string | null = 'PendingReview';
  protected facilityId: number | null = null;
  protected inventoryKind: string | null = null;
  protected page = 1;
  protected pageSize = 20;
  protected readonly statuses = [
    { value: 'PendingReview', label: 'Pending review' },
    { value: 'Applied', label: 'Applied' },
    { value: 'Rejected', label: 'Rejected' },
  ];

  ngOnInit(): void {
    this.imports
      .facilityOptions()
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({ next: (f) => this.facilities.set(f), error: () => this.facilities.set([]) });
    this.load();
  }

  protected load(): void {
    this.state.set('loading');
    this.changes
      .search({
        status: this.status,
        facilityId: this.facilityId,
        inventoryKind: this.inventoryKind,
        page: this.page,
        pageSize: this.pageSize,
      })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (result) => {
          this.items.set(result.items);
          this.total.set(result.totalCount ?? result.items.length);
          this.state.set(result.items.length ? 'ready' : 'empty');
        },
        error: (err) => {
          this.error.set(errorMessage(err, 'The verification queue could not be loaded.'));
          this.state.set('error');
        },
      });
  }

  protected applyFilters(): void {
    this.page = 1;
    this.load();
  }

  protected onPage(event: PageEvent): void {
    this.page = event.pageIndex + 1;
    this.pageSize = event.pageSize;
    this.load();
  }

  protected emptyMessage(): string {
    return this.status === 'PendingReview'
      ? 'No changes are waiting for review. Anomalous updates (e.g. large jumps) will appear here.'
      : 'No inventory changes match these filters.';
  }

  protected flags(c: InventoryChange): { code: string; label: string; hint: string; icon: string }[] {
    return (c.anomalyFlags ?? '')
      .split(/[,;|]/)
      .map((f) => f.trim().toUpperCase())
      .filter(Boolean)
      .map((code) => ({ code, ...(FLAG_INFO[code] ?? { label: code, hint: code, icon: 'flag' }) }));
  }

  protected diffs(c: InventoryChange): ValueDiff[] {
    if (c.inventoryKind === 'Blood') {
      return [this.diff('Quantity', c.previousQuantity, c.proposedQuantity)];
    }
    const rows: ValueDiff[] = [this.diff('Available', c.previousAvailable, c.proposedAvailable)];
    if (c.proposedTotal !== null && c.proposedTotal !== undefined) {
      rows.push(this.diff('Total', null, c.proposedTotal, true));
    }
    if (c.proposedStatus) {
      rows.push({ label: 'Status', before: '—', after: c.proposedStatus, delta: null, changed: true });
    }
    return rows;
  }

  private diff(label: string, before: number | null, after: number | null, onlyAfter = false): ValueDiff {
    const fmt = (v: number | null | undefined) => (v === null || v === undefined ? 'Not reported' : String(v));
    let delta: string | null = null;
    if (!onlyAfter && before !== null && before !== undefined && after !== null && after !== undefined) {
      const d = after - before;
      const pct = before !== 0 ? ` (${d > 0 ? '+' : ''}${Math.round((d / before) * 100)}%)` : '';
      delta = `${d > 0 ? '+' : ''}${d}${pct}`;
    }
    return { label, before: onlyAfter ? '—' : fmt(before), after: fmt(after), delta, changed: before !== after };
  }

  protected canDecide(c: InventoryChange): boolean {
    return this.canVerify() && c.status === 'PendingReview' && c.canDecide !== false;
  }

  protected async decide(c: InventoryChange, decision: ChangeDecision): Promise<void> {
    if (!this.canDecide(c)) {
      return;
    }
    let reason: string | null;
    if (decision === 'Reject') {
      reason = await this.ui.reason({
        title: `Reject ${c.changeNo}`,
        label: 'Reason for rejection (shared with the submitter)',
        required: true,
      });
      if (reason === null) return;
      reason = reason.trim();
      if (!reason) {
        this.ui.error('A rejection reason is required.');
        return;
      }
    } else {
      reason = await this.ui.reason({
        title: `Approve ${c.changeNo}`,
        label: 'Verification note (optional)',
        required: false,
      });
      if (reason === null) return;
      reason = reason.trim() || 'Verified with facility';
    }

    this.busyId.set(c.changeId);
    this.changes
      .decide(c.changeId, decision, reason, c.rowVersion)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: () => {
          this.busyId.set(null);
          this.ui.success(`${c.changeNo} ${decision === 'Approve' ? 'approved and applied' : 'rejected'}.`);
          this.load();
        },
        error: (err) => {
          this.busyId.set(null);
          if (err instanceof ApiError && err.status === 409) {
            this.ui.error(`${err.message || 'This change was already decided or the stock changed.'} The queue has been refreshed.`);
            this.load();
          } else if (err instanceof ApiError && err.status === 403) {
            this.ui.error(err.message || 'You cannot decide this change (you may be the submitter).');
          } else {
            this.ui.error(errorMessage(err, 'The decision could not be saved.'));
          }
        },
      });
  }

  protected statusClass(status: string): string {
    return `chg-status chg-status--${(status || '').toLowerCase()}`;
  }
}
