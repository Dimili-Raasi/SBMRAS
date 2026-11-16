import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { PagedResult, QueryParams } from '../models/api.models';
import {
  BloodStockItem,
  BloodStockUpdate,
  Facility,
  FacilityDetail,
  FacilityUpdate,
  InventoryChange,
  InventorySnapshot,
  ResourceInventoryItem,
  ResourceInventoryUpdate,
} from '../models/operations.models';
import { ApiService } from './api.service';

@Injectable({ providedIn: 'root' })
export class OperationsService {
  private readonly api = inject(ApiService);

  searchFacilities(query: QueryParams = {}): Observable<PagedResult<Facility>> {
    return this.api.getPaged<Facility>('facilities', query);
  }

  getFacility(facilityId: number): Observable<FacilityDetail> {
    return this.api.get<FacilityDetail>(`facilities/${facilityId}`);
  }

  updateFacility(facilityId: number, update: FacilityUpdate): Observable<Facility> {
    return this.api.put<Facility>(`facilities/${facilityId}`, update);
  }

  getResourceInventory(facilityId: number): Observable<ResourceInventoryItem[]> {
    return this.api.get<ResourceInventoryItem[]>(`facilities/${facilityId}/resources`);
  }

  submitResourceUpdate(facilityId: number, update: ResourceInventoryUpdate): Observable<unknown> {
    return this.api.post<unknown>(`facilities/${facilityId}/resources/updates`, update);
  }

  getBloodStock(facilityId: number): Observable<BloodStockItem[]> {
    return this.api.get<BloodStockItem[]>(`facilities/${facilityId}/blood-stock`);
  }

  submitBloodStockUpdate(facilityId: number, update: BloodStockUpdate): Observable<unknown> {
    return this.api.post<unknown>(`facilities/${facilityId}/blood-stock/updates`, update);
  }

  confirmBloodStock(facilityId: number, inventoryIds: number[]): Observable<unknown> {
    return this.api.post<unknown>(`facilities/${facilityId}/blood-stock/confirm`, { inventoryIds });
  }

  getInventoryHistory(facilityId: number, kind?: string, top = 30): Observable<InventorySnapshot[]> {
    return this.api.get<InventorySnapshot[]>(`facilities/${facilityId}/history`, { kind, top });
  }

  searchInventoryChanges(query: QueryParams = {}): Observable<PagedResult<InventoryChange>> {
    return this.api.getPaged<InventoryChange>('inventory-changes', query);
  }
}
