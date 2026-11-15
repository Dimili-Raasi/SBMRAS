import { DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, DestroyRef, OnInit, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { FormsModule } from '@angular/forms';
import { Subscription } from 'rxjs';
import { MatButtonModule } from '@angular/material/button';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatIconModule } from '@angular/material/icon';
import { MatInputModule } from '@angular/material/input';
import { MatPaginatorModule, PageEvent } from '@angular/material/paginator';

import { ViewState } from '../../../core/models/api.models';
import { AuditLog, AuditLogQuery } from '../../../core/models/insights.models';
import { Permissions } from '../../../core/models/permissions';
import { InsightsService } from '../../../core/services/insights.service';
import { SessionService } from '../../../core/services/session.service';
import { errorMessage } from '../../../core/utils/api-error';
import { PageHeader } from '../../../shared/components/page-header';
import { StatePanel } from '../../../shared/components/state-panel';

@Component({
  selector: 'sb-audit-logs',
  imports: [
    DatePipe,
    FormsModule,
    MatButtonModule,
    MatFormFieldModule,
    MatIconModule,
    MatInputModule,
    MatPaginatorModule,
    PageHeader,
    StatePanel,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './audit-logs.html',
  styleUrl: './audit-logs.scss',
})
export class AuditLogs implements OnInit {
  protected readonly permissions = Permissions;
  protected readonly session = inject(SessionService);

  private readonly insights = inject(InsightsService);
  private readonly destroyRef = inject(DestroyRef);
  private searchSubscription?: Subscription;

  protected readonly state = signal<ViewState>('loading');
  protected readonly error = signal('');
  protected readonly entries = signal<AuditLog[]>([]);
  protected readonly total = signal(0);
  protected readonly page = signal(1);
  protected readonly pageSize = signal(20);

  protected searchText = '';
  protected entityType = '';
  protected action = '';
  protected facilityId: number | null = null;
  protected userId: number | null = null;
  protected correlationId = '';
  protected fromDate = '';
  protected toDate = '';
  protected validationError = '';

  ngOnInit(): void {
    if (this.session.hasPermission(Permissions.AuditView)) this.load();
  }

  protected load(): void {
    if (!this.session.hasPermission(Permissions.AuditView)) return;
    this.searchSubscription?.unsubscribe();
    this.state.set('loading');
    this.error.set('');
    this.searchSubscription = this.insights
      .searchAuditLogs(this.query())
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (result) => {
          this.entries.set(result.items);
          this.total.set(result.totalCount);
          this.page.set(result.page);
          this.pageSize.set(result.pageSize);
          this.state.set(result.items.length ? 'ready' : 'empty');
        },
        error: (error) => {
          this.entries.set([]);
          this.error.set(errorMessage(error, 'Audit activity could not be loaded.'));
          this.state.set('error');
        },
      });
  }

  protected applyFilters(): void {
    this.validationError = '';
    if (this.fromDate && this.toDate && this.fromDate > this.toDate) {
      this.validationError = 'Start date must be on or before end date.';
      return;
    }
    this.page.set(1);
    this.load();
  }

  protected clearFilters(): void {
    this.searchText = '';
    this.entityType = '';
    this.action = '';
    this.facilityId = null;
    this.userId = null;
    this.correlationId = '';
    this.fromDate = '';
    this.toDate = '';
    this.validationError = '';
    this.page.set(1);
    this.load();
  }

  protected onPage(event: PageEvent): void {
    this.page.set(event.pageIndex + 1);
    this.pageSize.set(event.pageSize);
    this.load();
  }

  protected displayValue(value: string | null): string {
    if (!value) return '';
    try {
      return JSON.stringify(JSON.parse(value), null, 2);
    } catch {
      return value;
    }
  }

  private query(): AuditLogQuery {
    return {
      search: this.searchText.trim() || null,
      entityType: this.entityType.trim() || null,
      action: this.action.trim() || null,
      facilityId: this.facilityId,
      userId: this.userId,
      correlationId: this.correlationId.trim() || null,
      fromDate: this.fromDate || null,
      toDate: this.toDate || null,
      page: this.page(),
      pageSize: this.pageSize(),
    };
  }
}
