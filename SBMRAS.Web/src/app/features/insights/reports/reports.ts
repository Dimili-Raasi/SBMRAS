import { DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, DestroyRef, OnInit, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { FormsModule } from '@angular/forms';
import { Subscription } from 'rxjs';
import { MatButtonModule } from '@angular/material/button';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatIconModule } from '@angular/material/icon';
import { MatInputModule } from '@angular/material/input';
import { MatSelectModule } from '@angular/material/select';

import { ViewState } from '../../../core/models/api.models';
import {
  ReportColumn,
  ReportDefinition,
  ReportFacilityOption,
  ReportQuery,
  ReportResult,
} from '../../../core/models/insights.models';
import { Permissions } from '../../../core/models/permissions';
import { InsightsService } from '../../../core/services/insights.service';
import { SessionService } from '../../../core/services/session.service';
import { UiService } from '../../../core/services/ui.service';
import { errorMessage } from '../../../core/utils/api-error';
import { HasPermissionDirective } from '../../../core/directives/has-permission.directive';
import { ChartView } from '../../../shared/components/chart-view';
import { PageHeader } from '../../../shared/components/page-header';
import { StatePanel } from '../../../shared/components/state-panel';

@Component({
  selector: 'sb-reports',
  imports: [
    ChartView,
    FormsModule,
    HasPermissionDirective,
    MatButtonModule,
    MatFormFieldModule,
    MatIconModule,
    MatInputModule,
    MatSelectModule,
    PageHeader,
    StatePanel,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './reports.html',
  styleUrl: './reports.scss',
})
export class Reports implements OnInit {
  protected readonly permissions = Permissions;
  protected readonly session = inject(SessionService);

  private readonly insights = inject(InsightsService);
  private readonly ui = inject(UiService);
  private readonly destroyRef = inject(DestroyRef);
  private reportSubscription?: Subscription;

  protected readonly reportListState = signal<ViewState>('loading');
  protected readonly reportListError = signal('');
  protected readonly definitions = signal<ReportDefinition[]>([]);

  protected readonly facilityState = signal<ViewState>('loading');
  protected readonly facilityError = signal('');
  protected readonly facilities = signal<ReportFacilityOption[]>([]);

  protected readonly resultState = signal<ViewState>('empty');
  protected readonly resultError = signal('');
  protected readonly result = signal<ReportResult | null>(null);
  protected readonly exporting = signal(false);

  protected reportCode: string | null = null;
  protected fromDate = '';
  protected toDate = '';
  protected facilityId: number | null = null;
  protected validationError = '';

  ngOnInit(): void {
    if (!this.session.hasPermission(Permissions.ReportsView)) return;
    this.loadDefinitions();
    this.loadFacilities();
  }

  protected loadDefinitions(): void {
    this.reportListState.set('loading');
    this.reportListError.set('');
    this.insights
      .reports()
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (items) => {
          this.definitions.set(items);
          if (!items.length) {
            this.reportCode = null;
            this.reportListState.set('empty');
            this.resultState.set('empty');
            this.result.set(null);
            return;
          }
          if (!this.reportCode || !items.some((item) => item.code === this.reportCode)) {
            this.reportCode = items[0].code;
          }
          this.reportListState.set('ready');
          this.loadReport();
        },
        error: (error) => {
          this.reportListError.set(errorMessage(error, 'Report definitions could not be loaded.'));
          this.reportListState.set('error');
        },
      });
  }

  protected loadFacilities(): void {
    this.facilityState.set('loading');
    this.facilityError.set('');
    this.insights
      .reportFacilities()
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (items) => {
          this.facilities.set(items);
          this.facilityState.set(items.length ? 'ready' : 'empty');
        },
        error: (error) => {
          this.facilityError.set(errorMessage(error, 'Facility filters could not be loaded.'));
          this.facilityState.set('error');
        },
      });
  }

  protected onReportChange(): void {
    this.validationError = '';
    this.loadReport();
  }

  protected reportDescription(code: string): string {
    return this.definitions().find((item) => item.code === code)?.description ?? '';
  }

  protected applyFilters(): void {
    this.validationError = '';
    if (this.fromDate && this.toDate && this.fromDate > this.toDate) {
      this.validationError = 'Start date must be on or before end date.';
      return;
    }
    this.loadReport();
  }

  protected loadReport(): void {
    if (!this.reportCode) {
      this.result.set(null);
      this.resultState.set('empty');
      return;
    }
    if (this.fromDate && this.toDate && this.fromDate > this.toDate) {
      this.validationError = 'Start date must be on or before end date.';
      this.resultState.set('error');
      this.resultError.set(this.validationError);
      return;
    }
    this.reportSubscription?.unsubscribe();
    this.resultState.set('loading');
    this.resultError.set('');
    this.reportSubscription = this.insights
      .runReport(this.reportCode, this.query())
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (result) => {
          this.validationError = '';
          this.result.set(result);
          this.resultState.set(result.rows.length || result.chart?.labels.length ? 'ready' : 'empty');
        },
        error: (error) => {
          this.resultError.set(errorMessage(error, 'The selected report could not be run.'));
          this.resultState.set('error');
        },
      });
  }

  protected exportCsv(): void {
    if (!this.reportCode || this.exporting()) return;
    if (this.fromDate && this.toDate && this.fromDate > this.toDate) {
      this.validationError = 'Start date must be on or before end date.';
      return;
    }
    this.exporting.set(true);
    this.insights
      .exportReport(this.reportCode, this.query())
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: () => {
          this.exporting.set(false);
          this.ui.success('CSV export downloaded.');
        },
        error: (error) => {
          this.exporting.set(false);
          this.ui.error(errorMessage(error, 'The report could not be exported.'));
        },
      });
  }

  protected cell(row: Record<string, string | number | null>, column: ReportColumn): string {
    const value = row[column.key];
    if (value === null || value === undefined || value === '') return 'Not reported';
    if (column.type === 'date' && typeof value === 'string') {
      return new DatePipe('en').transform(value, 'mediumDate') ?? value;
    }
    if (column.type === 'number' && typeof value === 'number') {
      return new Intl.NumberFormat().format(value);
    }
    if (column.type === 'percent' && typeof value === 'number') {
      return `${new Intl.NumberFormat(undefined, { maximumFractionDigits: 2 }).format(value)}%`;
    }
    return String(value);
  }

  private query(): ReportQuery {
    return {
      fromDate: this.fromDate || null,
      toDate: this.toDate || null,
      facilityId: this.facilityId,
    };
  }
}
