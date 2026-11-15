import { Injectable, inject } from '@angular/core';
import { Observable, map } from 'rxjs';

import { PagedResult } from '../models/api.models';
import {
  BloodRequest,
  BloodRequestDetail,
  RequestMatch,
  RequestSave,
  RequestSearchQuery,
  RequestStatusChange,
} from '../models/requests.models';
import { ApiService } from './api.service';

/** Blood request endpoints (contract §6 Blood requests). */
@Injectable({ providedIn: 'root' })
export class RequestsService {
  private readonly api = inject(ApiService);

  search(query: RequestSearchQuery): Observable<PagedResult<BloodRequest>> {
    return this.api
      .get<PagedResult<BloodRequest>>('requests', { ...query })
      .pipe(map((page) => ({ ...page, items: page?.items ?? [], totalCount: page?.totalCount ?? 0 })));
  }

  getById(requestId: number): Observable<BloodRequestDetail> {
    return this.api.get<BloodRequestDetail>(`requests/${requestId}`).pipe(
      map((r) => ({
        ...r,
        history: r.history ?? [],
        allowedTransitions: r.allowedTransitions ?? [],
      })),
    );
  }

  create(body: RequestSave, idempotencyKey: string): Observable<BloodRequest> {
    return this.api.post<BloodRequest>('requests', body, { 'Idempotency-Key': idempotencyKey });
  }

  cancel(requestId: number, reason: string): Observable<BloodRequest> {
    return this.api.post<BloodRequest>(`requests/${requestId}/cancel`, { reason });
  }

  changeStatus(requestId: number, body: RequestStatusChange): Observable<BloodRequest> {
    return this.api.post<BloodRequest>(`requests/${requestId}/status`, body);
  }

  getMatches(requestId: number): Observable<RequestMatch[]> {
    return this.api.get<RequestMatch[]>(`requests/${requestId}/matches`).pipe(map((rows) => rows ?? []));
  }
}
