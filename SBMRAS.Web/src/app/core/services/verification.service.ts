import { Injectable, inject } from '@angular/core';
import { Observable, map } from 'rxjs';

import { PagedResult } from '../models/api.models';
import { ChangeDecision, InventoryChange, InventoryChangeQuery } from '../models/verification.models';
import { ApiService } from './api.service';

/** Inventory change verification endpoints (contract §6 Changes). */
@Injectable({ providedIn: 'root' })
export class VerificationService {
  private readonly api = inject(ApiService);

  search(query: InventoryChangeQuery): Observable<PagedResult<InventoryChange>> {
    return this.api
      .get<PagedResult<InventoryChange>>('inventory-changes', { ...query })
      .pipe(map((page) => ({ ...page, items: page?.items ?? [] })));
  }

  decide(
    changeId: number,
    decision: ChangeDecision,
    reason: string,
    rowVersion?: string | null,
  ): Observable<InventoryChange> {
    const body: Record<string, unknown> = { decision, reason };
    if (rowVersion) {
      body['rowVersion'] = rowVersion;
    }
    return this.api.post<InventoryChange>(`inventory-changes/${changeId}/decision`, body);
  }
}
