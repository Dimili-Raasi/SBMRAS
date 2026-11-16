import { Injectable, inject } from '@angular/core';
import { Observable, map } from 'rxjs';

import { PagedResult } from '../models/api.models';
import {
  DataQualitySummary,
  IssueQuery,
  ResolveIssueRequest,
  ScanResult,
  ValidationIssue,
} from '../models/data-quality.models';
import { ApiService } from './api.service';

/** Data quality endpoints (contract §6 Data quality). */
@Injectable({ providedIn: 'root' })
export class DataQualityService {
  private readonly api = inject(ApiService);

  summary(facilityId?: number | null): Observable<DataQualitySummary> {
    return this.api
      .get<DataQualitySummary>('data-quality/summary', { facilityId })
      .pipe(map((s) => ({ overall: s?.overall ?? null, facilities: s?.facilities ?? [] })));
  }

  issues(query: IssueQuery): Observable<PagedResult<ValidationIssue>> {
    return this.api
      .get<PagedResult<ValidationIssue>>('data-quality/issues', { ...query })
      .pipe(map((page) => ({ ...page, items: page?.items ?? [] })));
  }

  resolve(issueId: number, body: ResolveIssueRequest): Observable<ValidationIssue> {
    return this.api.post<ValidationIssue>(`data-quality/issues/${issueId}/resolve`, body);
  }

  scan(facilityId?: number | null): Observable<ScanResult> {
    return this.api.post<ScanResult>('data-quality/scan', { facilityId: facilityId ?? null });
  }
}
