import { ChangeDetectionStrategy, Component, DestroyRef, OnInit, computed, inject, input, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';
import { MatTooltipModule } from '@angular/material/tooltip';
import { Observable } from 'rxjs';

import { ViewState } from '../../../core/models/api.models';
import { Permissions } from '../../../core/models/permissions';
import {
  BloodRequest,
  BloodRequestDetail,
  OWNER_CANCELLABLE_STATUSES,
  RequestMatch,
  RequestStatus,
} from '../../../core/models/requests.models';
import { RequestsService } from '../../../core/services/requests.service';
import { SessionService } from '../../../core/services/session.service';
import { UiService } from '../../../core/services/ui.service';
import { HasPermissionDirective } from '../../../core/directives/has-permission.directive';
import { PageHeader } from '../../../shared/components/page-header';
import { StatePanel } from '../../../shared/components/state-panel';
import { StatusChip } from '../../../shared/components/status-chip';
import { UrgencyBadge } from '../../../shared/components/urgency-badge';
import { BloodGroupTile } from '../../../shared/components/blood-group-tile';
import { FreshnessBadge } from '../../../shared/components/freshness-badge';
import { SbDatePipe } from '../../../shared/pipes/sb-date.pipe';
import { SbRelativePipe } from '../../../shared/pipes/sb-relative.pipe';
import { SbQtyPipe } from '../../../shared/pipes/sb-qty.pipe';
import {
  TRANSITION_ACTIONS,
  TransitionAction,
  isConflict,
  requestErrorText,
  slaLevel,
  slaText,
  statusLabel,
} from '../requests-shared';

export type RequestViewMode = 'requester' | 'coordination';

/** Request detail (/requests/:id) and, in coordination mode, the management panel (/coordination/:id). */
@Component({
  selector: 'sb-request-view',
  imports: [
    RouterLink,
    MatButtonModule,
    MatIconModule,
    MatProgressSpinnerModule,
    MatTooltipModule,
    HasPermissionDirective,
    PageHeader,
    StatePanel,
    StatusChip,
    UrgencyBadge,
    BloodGroupTile,
    FreshnessBadge,
    SbDatePipe,
    SbRelativePipe,
    SbQtyPipe,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './request-view.html',
  styleUrl: './request-view.scss',
})
export class RequestView implements OnInit {
  readonly mode = input<RequestViewMode>('requester');

  private readonly requests = inject(RequestsService);
  private readonly session = inject(SessionService);
  private readonly ui = inject(UiService);
  private readonly route = inject(ActivatedRoute);
  private readonly destroyRef = inject(DestroyRef);

  protected readonly P = Permissions;
  protected readonly statusLabel = statusLabel;
  protected readonly slaLevel = slaLevel;
  protected readonly slaText = slaText;

  protected readonly requestId = signal<number | null>(null);
  protected readonly state = signal<ViewState>('loading');
  protected readonly error = signal('');
  protected readonly request = signal<BloodRequestDetail | null>(null);
  protected readonly busy = signal(false);
  protected readonly actionError = signal('');
  protected readonly conflict = signal(false);

  protected readonly matchesState = signal<ViewState>('loading');
  protected readonly matchesError = signal('');
  protected readonly matches = signal<RequestMatch[]>([]);

  protected readonly isCoordination = computed(() => this.mode() === 'coordination');
  protected readonly canManage = computed(() => this.session.hasPermission(Permissions.RequestsManage));
  protected readonly backLink = computed(() => (this.isCoordination() ? '/coordination' : '/requests'));

  protected readonly history = computed(() =>
    [...(this.request()?.history ?? [])].sort(
      (a, b) => new Date(b.changedAt).getTime() - new Date(a.changedAt).getTime(),
    ),
  );

  protected readonly canOwnerCancel = computed(() => {
    const r = this.request();
    return !!r && r.isOwner && OWNER_CANCELLABLE_STATUSES.includes(r.status);
  });

  /** Coordination actions = server-provided allowed transitions (state machine §4.5), Matched handled via matches. */
  protected readonly actions = computed<TransitionAction[]>(() => {
    const r = this.request();
    if (!r || !this.isCoordination() || !this.canManage()) {
      return [];
    }
    return r.allowedTransitions
      .filter((s) => s !== 'Matched')
      .map((s) => TRANSITION_ACTIONS[s])
      .filter((a): a is TransitionAction => !!a);
  });

  protected readonly canMatch = computed(
    () => this.isCoordination() && this.canManage() && !!this.request()?.allowedTransitions.includes('Matched'),
  );

  protected readonly showMatches = computed(() => {
    const r = this.request();
    return (
      !!r &&
      this.isCoordination() &&
      this.canManage() &&
      !['Fulfilled', 'Closed', 'Cancelled'].includes(r.status)
    );
  });

  ngOnInit(): void {
    this.route.paramMap.pipe(takeUntilDestroyed(this.destroyRef)).subscribe((params) => {
      const id = Number(params.get('id'));
      this.requestId.set(Number.isInteger(id) && id > 0 ? id : null);
      this.reload();
    });
  }

  reload(): void {
    const id = this.requestId();
    this.actionError.set('');
    this.conflict.set(false);
    if (!id) {
      this.request.set(null);
      this.error.set('The request reference is not valid.');
      this.state.set('error');
      return;
    }
    this.state.set('loading');
    this.error.set('');
    this.requests
      .getById(id)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (r) => {
          this.request.set(r);
          this.state.set('ready');
          if (this.showMatches()) {
            this.loadMatches();
          }
        },
        error: (err) => {
          this.request.set(null);
          this.error.set(requestErrorText(err));
          this.state.set('error');
        },
      });
  }

  protected loadMatches(): void {
    const id = this.requestId();
    if (!id) {
      return;
    }
    this.matchesState.set('loading');
    this.matchesError.set('');
    this.requests
      .getMatches(id)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (rows) => {
          this.matches.set(rows);
          this.matchesState.set(rows.length ? 'ready' : 'empty');
        },
        error: (err) => {
          this.matches.set([]);
          this.matchesError.set(requestErrorText(err));
          this.matchesState.set('error');
        },
      });
  }

  protected async ownerCancel(): Promise<void> {
    const r = this.request();
    if (!r || this.busy()) {
      return;
    }
    const reason = await this.ui.reason({
      title: `Cancel ${r.requestNo}`,
      label: 'Why are you cancelling this request?',
      required: true,
    });
    if (reason === null || !reason.trim()) {
      return;
    }
    this.run(this.requests.cancel(r.requestId, reason.trim()), 'Request cancelled.');
  }

  protected async transition(action: TransitionAction): Promise<void> {
    const r = this.request();
    if (!r || this.busy()) {
      return;
    }
    const note = await this.ui.reason({
      title: `${action.title} — ${r.requestNo}`,
      label: action.reasonLabel,
      required: action.reasonRequired,
    });
    if (note === null || (action.reasonRequired && !note.trim())) {
      return;
    }
    this.change(r, action.toStatus, note.trim() || null, null, `Request moved to ${statusLabel(action.toStatus)}.`);
  }

  protected async matchTo(match: RequestMatch): Promise<void> {
    const r = this.request();
    if (!r || this.busy() || !this.canMatch()) {
      return;
    }
    const note = await this.ui.reason({
      title: `Match ${r.requestNo} to ${match.facilityName}`,
      label: 'Match note (optional) — stock must be reconfirmed with the facility',
      required: false,
    });
    if (note === null) {
      return;
    }
    this.change(r, 'Matched', note.trim() || null, match.facilityId, `Matched to ${match.facilityName}.`);
  }

  protected tel(phone: string | null | undefined): string | null {
    return phone ? `tel:${phone.replace(/[^0-9+]/g, '')}` : null;
  }

  private change(
    r: BloodRequest,
    toStatus: RequestStatus,
    note: string | null,
    matchedFacilityId: number | null,
    successMessage: string,
  ): void {
    this.run(
      this.requests.changeStatus(r.requestId, {
        toStatus,
        note,
        matchedFacilityId: matchedFacilityId ?? r.matchedFacilityId ?? null,
        rowVersion: r.rowVersion,
      }),
      successMessage,
    );
  }

  private run(call: Observable<unknown>, successMessage: string): void {
    this.busy.set(true);
    this.actionError.set('');
    this.conflict.set(false);
    call.pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
      next: () => {
        this.busy.set(false);
        this.ui.success(successMessage);
        this.reload();
      },
      error: (err) => {
        this.busy.set(false);
        this.conflict.set(isConflict(err));
        this.actionError.set(requestErrorText(err));
      },
    });
  }
}
