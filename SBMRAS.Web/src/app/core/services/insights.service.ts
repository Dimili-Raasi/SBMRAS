import { Injectable, inject } from '@angular/core';
import { Observable, map } from 'rxjs';

import { PagedResult } from '../models/api.models';
import {
  AuditLog,
  AuditLogQuery,
  DashboardActivityItem,
  DashboardCharts,
  DashboardSummary,
  DashboardWorklistItem,
  ReportDefinition,
  ReportFacilityOption,
  ReportQuery,
  ReportResult,
} from '../models/insights.models';
import { ApiService } from './api.service';

@Injectable({ providedIn: 'root' })
export class InsightsService {
  private readonly api = inject(ApiService);

  dashboardSummary(): Observable<DashboardSummary | null> {
    return this.api.get<DashboardSummary | null>('dashboard/summary');
  }

  dashboardCharts(): Observable<DashboardCharts> {
    return this.api.get<DashboardCharts>('dashboard/charts').pipe(
      map((charts) => ({
        bloodByGroup: charts?.bloodByGroup ?? [],
        freshness: charts?.freshness ?? [],
        requestTrend: charts?.requestTrend ?? [],
        requestStatus: charts?.requestStatus ?? [],
        resourceUtilization: charts?.resourceUtilization ?? [],
        qualityByFacility: charts?.qualityByFacility ?? [],
      })),
    );
  }

  dashboardWorklist(): Observable<DashboardWorklistItem[]> {
    return this.api
      .get<DashboardWorklistItem[]>('dashboard/worklist')
      .pipe(map((items) => items ?? []));
  }

  dashboardActivity(top = 10): Observable<DashboardActivityItem[]> {
    return this.api
      .get<DashboardActivityItem[]>('dashboard/activity', { top })
      .pipe(map((items) => items ?? []));
  }

  reports(): Observable<ReportDefinition[]> {
    return this.api.get<ReportDefinition[]>('reports').pipe(map((items) => items ?? []));
  }

  reportFacilities(): Observable<ReportFacilityOption[]> {
    return this.api
      .getPaged<ReportFacilityOption>('facilities', { page: 1, pageSize: 100 })
      .pipe(map((page) => page?.items ?? []));
  }

  runReport(code: string, query: ReportQuery): Observable<ReportResult> {
    return this.api
      .get<ReportResult>(`reports/${encodeURIComponent(code)}`, query)
      .pipe(
        map((result) => ({
          ...result,
          columns: result?.columns ?? [],
          rows: result?.rows ?? [],
          chart: result?.chart ?? null,
        })),
      );
  }

  exportReport(code: string, query: ReportQuery): Observable<Blob> {
    return this.api.download(
      `reports/${encodeURIComponent(code)}/export`,
      query,
      `${code.toLowerCase().replace(/[^a-z0-9]+/g, '-')}.csv`,
    );
  }

  searchAuditLogs(query: AuditLogQuery): Observable<PagedResult<AuditLog>> {
    return this.api.getPaged<AuditLog>('audit-logs', query).pipe(
      map((page) => ({
        ...page,
        items: page?.items ?? [],
        totalCount: page?.totalCount ?? 0,
        page: page?.page ?? query.page,
        pageSize: page?.pageSize ?? query.pageSize,
      })),
    );
  }
}

