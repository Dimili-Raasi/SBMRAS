import { QueryParams } from './api.models';

export interface PublicStats {
  verifiedFacilities: number | null;
  hospitals: number | null;
  bloodBanks: number | null;
  unitsAvailable: number | null;
  freshPercent: number | null;
  openRequests: number | null;
  fulfilledRequests: number | null;
  lastUpdatedAt: string | null;
}

export interface BloodAvailability {
  inventoryId: number;
  facilityId: number;
  facilityName: string;
  facilityType: string;
  areaId: number;
  areaName: string | null;
  city: string | null;
  addressLine: string | null;
  contactPhone: string | null;
  is24x7: boolean;
  componentId: number;
  componentCode: string | null;
  componentName: string | null;
  aboGroup: string;
  rhFactor: string;
  bloodGroup: string | null;
  quantity: number | null;
  unitCode: string | null;
  availabilityStatus: string | null;
  freshnessStatus: string | null;
  verificationStatus: string | null;
  sourceType: string | null;
  lastUpdatedAt: string | null;
  validUntil: string | null;
  minutesSinceUpdate: number | null;
  earliestExpiryDate: string | null;
  qualityScore: number | null;
}

export interface ResourceAvailability {
  resourceInventoryId: number;
  facilityId: number;
  facilityName: string;
  areaId: number;
  areaName: string | null;
  city: string | null;
  contactPhone: string | null;
  is24x7: boolean;
  categoryName: string | null;
  resourceTypeId: number;
  resourceTypeCode: string | null;
  resourceTypeName: string;
  totalQuantity: number | null;
  availableQuantity: number | null;
  unitCode: string | null;
  operationalStatus: string | null;
  freshnessStatus: string | null;
  verificationStatus: string | null;
  lastUpdatedAt: string | null;
  validUntil: string | null;
  minutesSinceUpdate: number | null;
  notes: string | null;
}

export interface PublicFacility {
  facilityId: number;
  facilityCode: string;
  name: string;
  facilityType: 'Hospital' | 'BloodBank' | string;
  addressLine: string | null;
  areaName: string | null;
  city: string | null;
  contactPhone: string | null;
  contactEmail: string | null;
  is24x7: boolean;
  qualityScore: number | null;
  lastUpdateAt: string | null;
}

export interface BloodSearchQuery extends QueryParams {
  aboGroup?: string | null;
  rhFactor?: string | null;
  componentId?: number | null;
  areaId?: number | null;
  search?: string | null;
  freshOnly?: boolean;
  minQuantity?: number | null;
  page?: number;
  pageSize?: number;
}

export interface ResourceSearchQuery extends QueryParams {
  categoryId?: number | null;
  resourceTypeId?: number | null;
  areaId?: number | null;
  search?: string | null;
  availableOnly?: boolean;
  freshOnly?: boolean;
  page?: number;
  pageSize?: number;
}

export interface FacilitySearchQuery extends QueryParams {
  facilityType?: string | null;
  areaId?: number | null;
  search?: string | null;
  page?: number;
  pageSize?: number;
}
