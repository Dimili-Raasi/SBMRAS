import { Injectable, inject } from '@angular/core';
import { Observable, map } from 'rxjs';

import { PagedResult } from '../models/api.models';
import {
  ImportBatch,
  ImportBatchCreate,
  ImportBatchDetail,
  ImportBatchQuery,
  ImportFacilityOption,
} from '../models/imports.models';
import { ApiService } from './api.service';

/** Bulk import endpoints (contract §6 Imports). CSV files are parsed in the browser; only JSON rows are posted. */
@Injectable({ providedIn: 'root' })
export class ImportsService {
  private readonly api = inject(ApiService);

  search(query: ImportBatchQuery): Observable<PagedResult<ImportBatch>> {
    return this.api
      .get<PagedResult<ImportBatch>>('imports', { ...query })
      .pipe(map((page) => ({ ...page, items: page?.items ?? [] })));
  }

  getById(batchId: number): Observable<ImportBatchDetail> {
    return this.api.get<ImportBatchDetail>(`imports/${batchId}`).pipe(map(normalizeDetail));
  }

  /** Stages + validates the parsed rows; returns the batch with per-row validation results. */
  stage(body: ImportBatchCreate): Observable<ImportBatchDetail> {
    return this.api.post<ImportBatchDetail>('imports', body).pipe(map(normalizeDetail));
  }

  commit(batchId: number, idempotencyKey: string): Observable<ImportBatchDetail> {
    return this.api
      .post<ImportBatchDetail>(`imports/${batchId}/commit`, {}, { 'Idempotency-Key': idempotencyKey })
      .pipe(map(normalizeDetail));
  }

  cancel(batchId: number): Observable<ImportBatchDetail> {
    return this.api.post<ImportBatchDetail>(`imports/${batchId}/cancel`, {}).pipe(map(normalizeDetail));
  }

  /** Facilities the user can import into (assigned facilities; all for data.viewall). */
  facilityOptions(): Observable<ImportFacilityOption[]> {
    return this.api
      .get<PagedResult<ImportFacilityOption>>('facilities', { page: 1, pageSize: 200 })
      .pipe(map((page) => page?.items ?? []));
  }
}

function normalizeDetail(detail: ImportBatchDetail | null): ImportBatchDetail {
  const value = (detail ?? {}) as ImportBatchDetail & { batch?: ImportBatch };
  // Tolerate `{ batch: {...}, rows: [...] }` as well as a flattened batch.
  const batch = value.batch ? { ...value.batch } : value;
  return { ...(batch as ImportBatch), rows: value.rows ?? [] };
}
