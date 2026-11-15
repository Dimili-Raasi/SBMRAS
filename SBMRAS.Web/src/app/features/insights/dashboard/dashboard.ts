import { DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, DestroyRef, OnInit, computed, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { RouterLink } from '@angular/router';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';

import { ViewState } from '../../../core/models/api.models';
import {
  DashboardActivityItem,
  DashboardCharts,
  DashboardSummary,
  DashboardWorklistItem,
} from '../../../core/models/insights.models';
import { Permissions } from '../../../core/models/permissions';
import { InsightsService } from '../../../core/services/insights.service';
import { SessionService } from '../../../core/services/session.service';
import { errorMessage } from '../../../core/utils/api-error';
import { ChartView } from '../../../shared/components/chart-view';
import { KpiCard } from '../../../shared/components/kpi-card';
import { PageHeader } from '../../../shared/components/page-header';
import { QualityGauge } from '../../../shared/components/quality-gauge';
import { StatePanel } from '../../../shared/components/state-panel';

@Component({
  selector: 'sb-dashboard',
  imports: [ChartView, DatePipe, KpiCard, MatButtonModule, MatIconModule, PageHeader, QualityGauge, RouterLink, StatePanel],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './dashboard.html',
  styleUrl: './dashboard.scss',
})
export class Dashboard implements OnInit {
  protected readonly permissions = Permissions;
  protected readonly session = inject(SessionService);

  private readonly insights = inject(InsightsService);
  private readonly destroyRef = inject(DestroyRef);

  protected readonly summaryState = signal<ViewState>('loading');
  protected readonly summaryError = signal('');
  protected readonly summary = signal<DashboardSummary | null>(null);

  protected readonly chartState = signal<ViewState>('loading');
  protected readonly chartError = signal('');
  protected readonly charts = signal<DashboardCharts | null>(null);

  protected readonly worklistState = signal<ViewState>('loading');
  protected readonly worklistError = signal('');
  protected readonly worklist = signal<DashboardWorklistItem[]>([]);

  protected readonly activityState = signal<ViewState>('loading');
  protected readonly activityError = signal('');
  protected readonly activity = signal<DashboardActivityItem[]>([]);

  protected readonly isPublicUser = computed(
    () => this.session.user()?.primaryRole === 'PublicUser' || this.session.user()?.roles.includes('PublicUser') === true,
  );
  protected readonly requestTrend = computed(() => {
    const points = (this.charts()?.requestTrend ?? []).filter(
      (point) => point.submitted !== null && point.submitted !== undefined && point.fulfilled !== null && point.fulfilled !== undefined,
    );
    return {
      labels: points.map((point) => point.label),
      datasets: [
        { label: 'Submitted', data: points.map((point) => point.submitted as number), color: '#c8102e' },
        { label: 'Fulfilled', data: points.map((point) => point.fulfilled as number), color: '#00897b' },
      ],
    };
  });
  protected readonly freshnessChart = computed(() => {
    const points = (this.charts()?.freshness ?? []).filter(
      (point) => point.value !== null && point.value !== undefined,
    );
    return {
      labels: points.map((point) => point.label),
      datasets: [{ label: 'Records', data: points.map((point) => point.value as number), color: '#00897b' }],
    };
  });

  ngOnInit(): void {
    if (this.session.hasPermission(Permissions.DashboardView)) this.reload();
  }

  protected reload(): void {
    if (!this.session.hasPermission(Permissions.DashboardView)) return;
    this.loadSummary();
    this.loadCharts();
    this.loadWorklist();
    this.loadActivity();
  }

  protected loadSummary(): void {
    this.summaryState.set('loading');
    this.summaryError.set('');
    this.insights
      .dashboardSummary()
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (summary) => {
          this.summary.set(summary);
          this.summaryState.set(summary ? 'ready' : 'empty');
        },
        error: (error) => {
          this.summaryError.set(errorMessage(error, 'Dashboard totals could not be loaded.'));
          this.summaryState.set('error');
        },
      });
  }

  protected loadCharts(): void {
    this.chartState.set('loading');
    this.chartError.set('');
    this.insights
      .dashboardCharts()
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (charts) => {
          this.charts.set(charts);
          const anyData =
            charts.requestTrend.length ||
            charts.freshness.length ||
            charts.bloodByGroup.length ||
            charts.requestStatus.length ||
            charts.resourceUtilization.length ||
            charts.qualityByFacility.length;
          this.chartState.set(anyData ? 'ready' : 'empty');
        },
        error: (error) => {
          this.chartError.set(errorMessage(error, 'Dashboard trends could not be loaded.'));
          this.chartState.set('error');
        },
      });
  }

  protected loadWorklist(): void {
    this.worklistState.set('loading');
    this.worklistError.set('');
    this.insights
      .dashboardWorklist()
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (items) => {
          this.worklist.set(items);
          this.worklistState.set(items.length ? 'ready' : 'empty');
        },
        error: (error) => {
          this.worklistError.set(errorMessage(error, 'Your worklist could not be loaded.'));
          this.worklistState.set('error');
        },
      });
  }

  protected loadActivity(): void {
    this.activityState.set('loading');
    this.activityError.set('');
    this.insights
      .dashboardActivity()
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (items) => {
          this.activity.set(items);
          this.activityState.set(items.length ? 'ready' : 'empty');
        },
        error: (error) => {
          this.activityError.set(errorMessage(error, 'Recent activity could not be loaded.'));
          this.activityState.set('error');
        },
      });
  }

  protected metric(value: number | null | undefined, percent = false): string {
    if (value === null || value === undefined) return 'Not reported';
    return percent ? `${this.formatNumber(value)}%` : this.formatNumber(value);
  }

  protected formatNumber(value: number): string {
    return new Intl.NumberFormat().format(value);
  }

  protected metricCards(summary: DashboardSummary): {
    label: string;
    value: number | string | null;
    icon: string;
    hint: string;
    route: string | null;
  }[] {
    if (this.isPublicUser()) {
      return [
        { label: 'My open requests', value: summary.myOpenRequests, icon: 'assignment', hint: 'Requests you created', route: '/requests' },
        { label: 'Emergency requests', value: summary.emergencyRequests, icon: 'emergency', hint: 'In your visible scope', route: '/requests' },
        { label: 'Fulfilled requests', value: summary.fulfilledRequests, icon: 'task_alt', hint: 'In your visible scope', route: '/requests' },
      ];
    }

    return [
      { label: 'Facilities', value: summary.totalFacilities, icon: 'apartment', hint: `${this.metric(summary.verifiedFacilities)} verified`, route: this.routeIfAllowed('/facilities', Permissions.FacilitiesView) },
      { label: 'Blood units available', value: summary.bloodUnitsAvailable, icon: 'water_drop', hint: 'Reported across your scope', route: this.routeIfAllowed('/blood-stock', Permissions.BloodStockManage) },
      { label: 'Fresh records', value: this.metric(summary.freshPercent, true), icon: 'update', hint: 'Of reported inventory', route: this.routeIfAllowed('/data-quality', Permissions.DataQualityView) },
      { label: 'Open requests', value: summary.openRequests, icon: 'assignment', hint: `${this.metric(summary.emergencyRequests)} emergency`, route: this.routeIfAllowed('/coordination', Permissions.RequestsManage) },
      { label: 'Pending reviews', value: summary.pendingReviews, icon: 'fact_check', hint: 'Awaiting verification', route: this.routeIfAllowed('/verifications', Permissions.InventoryVerify) },
      { label: 'Open data issues', value: summary.openIssues, icon: 'report_problem', hint: 'Quality findings', route: this.routeIfAllowed('/data-quality', Permissions.DataQualityView) },
    ];
  }

  protected cardValue(value: number | string | null): number | string {
    if (value === null || value === undefined) return 'Not reported';
    return value;
  }

  protected routeIfAllowed(route: string, permission: string): string | null {
    return this.session.hasPermission(permission) ? route : null;
  }
}
