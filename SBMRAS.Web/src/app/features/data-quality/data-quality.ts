import { ChangeDetectionStrategy, Component, DestroyRef, OnInit, computed, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { DatePipe, DecimalPipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { MatButtonModule } from '@angular/material/button';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatIconModule } from '@angular/material/icon';
import { MatPaginatorModule, PageEvent } from '@angular/material/paginator';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';
import { MatSelectModule } from '@angular/material/select';
import { MatTooltipModule } from '@angular/material/tooltip';

import { ViewState } from '../../core/models/api.models';
import {
  DataQualitySummary,
  FacilityQuality,
  ISSUE_CODES,
  QualityScores,
  ValidationIssue,
} from '../../core/models/data-quality.models';
import { DataQualityService } from '../../core/services/data-quality.service';
import { UiService } from '../../core/services/ui.service';
import { ApiError, errorMessage } from '../../core/utils/api-error';
import { PageHeader } from '../../shared/components/page-header';
import { QualityGauge } from '../../shared/components/quality-gauge';
import { StatePanel } from '../../shared/components/state-panel';

interface FreshnessSegment {
  key: 'fresh' | 'aging' | 'stale' | 'unknown' | 'underReview';
  label: string;
  color: string;
  value: number | null;
  pct: number;
}

const SEGMENTS: Omit<FreshnessSegment, 'value' | 'pct'>[] = [
  { key: 'fresh', label: 'Fresh', color: '#2E9E5B' },
  { key: 'aging', label: 'Aging', color: '#F2A900' },
  { key: 'stale', label: 'Stale', color: '#D93025' },
  { key: 'unknown', label: 'Unknown', color: '#8A96A3' },
  { key: 'underReview', label: 'Under review', color: '#7B4FD6' },
];

@Component({
  selector: 'sb-data-quality',
  imports: [
    DatePipe,
    DecimalPipe,
    FormsModule,
    MatButtonModule,
    MatFormFieldModule,
    MatIconModule,
    MatPaginatorModule,
    MatProgressSpinnerModule,
    MatSelectModule,
    MatTooltipModule,
    PageHeader,
    QualityGauge,
    StatePanel,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './data-quality.html',
  styleUrl: './data-quality.scss',
})
export class DataQuality implements OnInit {
  private readonly dq = inject(DataQualityService);
  private readonly ui = inject(UiService);
  private readonly destroyRef = inject(DestroyRef);

  protected readonly issueCodes = ISSUE_CODES;
  protected readonly severities = ['High', 'Medium', 'Low'];
  protected readonly issueStatuses = ['Open', 'Resolved', 'Dismissed'];

  protected readonly summaryState = signal<ViewState>('loading');
  protected readonly summaryError = signal('');
  protected readonly summary = signal<DataQualitySummary | null>(null);
  protected readonly facilityOptions = signal<FacilityQuality[]>([]);

  protected readonly issueState = signal<ViewState>('loading');
  protected readonly issueError = signal('');
  protected readonly issues = signal<ValidationIssue[]>([]);
  protected readonly issueTotal = signal(0);
  protected readonly busyIssueId = signal<number | null>(null);
  protected readonly scanning = signal(false);

  protected facilityId: number | null = null;
  protected status: string | null = 'Open';
  protected severity: string | null = null;
  protected issueCode: string | null = null;
  protected page = 1;
  protected pageSize = 20;

  protected readonly overall = computed(() => this.summary()?.overall ?? null);
  protected readonly freshness = computed(() => this.segments(this.overall()));
  protected readonly facilities = computed(() =>
    [...(this.summary()?.facilities ?? [])].sort((a, b) => (a.qualityScore ?? 101) - (b.qualityScore ?? 101)),
  );

  ngOnInit(): void {
    this.loadSummary();
    this.loadIssues();
  }

  protected reloadAll(): void {
    this.loadSummary();
    this.loadIssues();
  }

  protected loadSummary(): void {
    this.summaryState.set('loading');
    this.dq
      .summary(this.facilityId)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (s) => {
          this.summary.set(s);
          if (!this.facilityId) {
            this.facilityOptions.set(s.facilities);
          }
          this.summaryState.set(s.overall || s.facilities.length ? 'ready' : 'empty');
        },
        error: (err) => {
          this.summaryError.set(errorMessage(err, 'Quality scores could not be loaded.'));
          this.summaryState.set('error');
        },
      });
  }

  protected loadIssues(): void {
    this.issueState.set('loading');
    this.dq
      .issues({
        facilityId: this.facilityId,
        status: this.status,
        severity: this.severity,
        issueCode: this.issueCode,
        page: this.page,
        pageSize: this.pageSize,
      })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (result) => {
          this.issues.set(result.items);
          this.issueTotal.set(result.totalCount ?? result.items.length);
          this.issueState.set(result.items.length ? 'ready' : 'empty');
        },
        error: (err) => {
          this.issueError.set(errorMessage(err, 'Validation issues could not be loaded.'));
          this.issueState.set('error');
        },
      });
  }

  protected onFacilityChange(): void {
    this.page = 1;
    this.reloadAll();
  }

  protected applyIssueFilters(): void {
    this.page = 1;
    this.loadIssues();
  }

  protected onPage(event: PageEvent): void {
    this.page = event.pageIndex + 1;
    this.pageSize = event.pageSize;
    this.loadIssues();
  }

  protected scan(): void {
    this.scanning.set(true);
    this.dq
      .scan(this.facilityId)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (r) => {
          this.scanning.set(false);
          this.ui.success(
            `Scan complete: ${r.staleFound ?? 0} stale, ${r.expiringFound ?? 0} expiring, ` +
              `${r.missingFound ?? 0} missing — ${r.issuesCreated ?? 0} new issue(s).`,
          );
          this.reloadAll();
        },
        error: (err) => {
          this.scanning.set(false);
          this.ui.error(errorMessage(err, 'The data quality scan failed.'));
        },
      });
  }

  protected async resolve(issue: ValidationIssue, dismiss: boolean): Promise<void> {
    const resolution = await this.ui.reason({
      title: `${dismiss ? 'Dismiss' : 'Resolve'} ${issue.issueCode} issue`,
      label: dismiss ? 'Why is this not a real problem?' : 'What was done to resolve it?',
      required: true,
    });
    if (resolution === null) return;
    if (!resolution.trim()) {
      this.ui.error('A resolution note is required.');
      return;
    }
    this.busyIssueId.set(issue.issueId);
    this.dq
      .resolve(issue.issueId, { resolution: resolution.trim(), dismiss })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: () => {
          this.busyIssueId.set(null);
          this.ui.success(`Issue ${dismiss ? 'dismissed' : 'resolved'}.`);
          this.reloadAll();
        },
        error: (err) => {
          this.busyIssueId.set(null);
          this.ui.error(
            err instanceof ApiError && err.status === 409
              ? `${err.message || 'This issue was already closed.'} The list has been refreshed.`
              : errorMessage(err, 'The issue could not be updated.'),
          );
          if (err instanceof ApiError && err.status === 409) this.loadIssues();
        },
      });
  }

  protected segments(scores: QualityScores | null): FreshnessSegment[] {
    const values = SEGMENTS.map((s) => ({ ...s, value: scores ? (scores[s.key] ?? null) : null }));
    const total = values.reduce((sum, v) => sum + (v.value ?? 0), 0);
    return values.map((v) => ({ ...v, pct: total > 0 ? ((v.value ?? 0) / total) * 100 : 0 }));
  }

  protected hasFreshnessData(scores: QualityScores | null): boolean {
    return this.segments(scores).some((s) => (s.value ?? 0) > 0);
  }

  protected score(value: number | null | undefined): string {
    return value === null || value === undefined ? 'Not reported' : `${Math.round(value)}`;
  }

  protected n(value: number | null | undefined): string {
    return value === null || value === undefined ? 'Not reported' : String(value);
  }

  protected scoreTone(value: number | null | undefined): string {
    if (value === null || value === undefined) return 'tone-unknown';
    return value >= 80 ? 'tone-good' : value >= 60 ? 'tone-warn' : 'tone-bad';
  }
}
