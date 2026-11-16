import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { PagedResult } from '../models/api.models';
import {
  BloodAvailability,
  BloodSearchQuery,
  FacilitySearchQuery,
  PublicFacility,
  PublicStats,
  ResourceAvailability,
  ResourceSearchQuery,
} from '../models/public.models';
import { ApiService } from './api.service';

@Injectable({ providedIn: 'root' })
export class PublicService {
  private readonly api = inject(ApiService);

  getStats(): Observable<PublicStats> {
    return this.api.get<PublicStats>('public/stats');
  }

  searchBlood(query: BloodSearchQuery): Observable<PagedResult<BloodAvailability>> {
    return this.api.getPaged<BloodAvailability>('public/blood-availability', query);
  }

  searchResources(query: ResourceSearchQuery): Observable<PagedResult<ResourceAvailability>> {
    return this.api.getPaged<ResourceAvailability>('public/medical-resources', query);
  }

  searchFacilities(query: FacilitySearchQuery): Observable<PagedResult<PublicFacility>> {
    return this.api.getPaged<PublicFacility>('public/facilities', query);
  }
}

export function publicErrorText(error: unknown): string {
  if (error && typeof error === 'object') {
    const value = error as { message?: unknown; errors?: unknown };
    if (Array.isArray(value.errors) && value.errors.length) {
      return value.errors.map(String).join(' ');
    }
    if (typeof value.message === 'string' && value.message.trim()) {
      return value.message;
    }
  }
  return 'We could not load public availability. Please try again.';
}
