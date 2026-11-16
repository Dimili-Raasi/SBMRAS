import { PagedResult } from './api.models';

export interface Facility {
  facilityId: number;
  facilityCode: string;
  name: string;
  facilityType: 'Hospital' | 'BloodBank' | string;
  licenseNo: string | null;
  addressLine: string | null;
  areaId: number | null;
  areaName: string | null;
  city: string | null;
  pincode: string | null;
  latitude: number | null;
  longitude: number | null;
  contactPhone: string | null;
  contactEmail: string | null;
  is24x7: boolean;
  verificationStatus: string;
  verifiedAt: string | null;
  verificationNotes: string | null;
  isActive: boolean;
  qualityScore: number | null;
  freshPercent: number | null;
  staleRecords: number | null;
  lastUpdateAt: string | null;
  rowVersion: string;
  createdAt: string;
}

export interface FacilityUser {
  userId: number;
  displayName: string;
  email: string;
  assignmentRole: string;
}

export interface FacilityQuality {
  qualityScore?: number | null;
  completenessScore?: number | null;
  recencyScore?: number | null;
  verificationScore?: number | null;
  anomalyScore?: number | null;
  [key: string]: unknown;
}

export interface FacilityDetail extends Facility {
  users: FacilityUser[];
  quality: FacilityQuality | null;
}

export type FacilitySearchResult = PagedResult<Facility>;

export interface FacilityUpdate {
  name: string;
  licenseNo: string | null;
  addressLine: string;
  areaId: number;
  city: string;
  pincode: string;
  latitude: number | null;
  longitude: number | null;
  contactPhone: string;
  contactEmail: string;
  is24x7: boolean;
  rowVersion: string;
}

export interface ResourceInventoryItem {
  resourceInventoryId: number | null;
  facilityId: number;
  resourceTypeId: number;
  resourceTypeCode: string;
  resourceTypeName: string;
  categoryName: string;
  trackingMode: string;
  totalQuantity: number | null;
  availableQuantity: number | null;
  unitId: number | null;
  unitCode: string | null;
  operationalStatus: string | null;
  notes: string | null;
  sourceType: string | null;
  verificationStatus: string | null;
  freshnessStatus: string;
  lastUpdatedAt: string | null;
  lastUpdatedByName: string | null;
  validUntil: string | null;
  rowVersion: string | null;
}

export interface ResourceInventoryUpdate {
  resourceTypeId: number;
  totalQuantity: number;
  availableQuantity: number;
  operationalStatus: string;
  validUntil: string | null;
  notes: string | null;
  reason: string;
  rowVersion: string | null;
}

export interface BloodStockItem {
  inventoryId: number | null;
  facilityId: number;
  componentId: number;
  componentCode: string;
  componentName: string;
  aboGroup: string;
  rhFactor: string;
  bloodGroup: string;
  quantity: number | null;
  unitCode: string | null;
  earliestExpiryDate: string | null;
  availabilityStatus: string | null;
  freshnessStatus: string;
  verificationStatus: string | null;
  sourceType: string | null;
  lastUpdatedAt: string | null;
  lastUpdatedByName: string | null;
  validUntil: string | null;
  rowVersion: string | null;
}

export interface BloodStockUpdate {
  componentId: number;
  aboGroup: string;
  rhFactor: string;
  quantity: number;
  earliestExpiryDate: string | null;
  validUntil: string | null;
  reason: string;
  rowVersion: string | null;
}

export interface InventoryChange {
  changeId: number;
  changeNo: string;
  facilityId: number;
  facilityName: string;
  inventoryKind: 'Blood' | 'Resource' | string;
  itemLabel: string;
  previousQuantity: number | null;
  proposedQuantity: number | null;
  previousAvailable: number | null;
  proposedAvailable: number | null;
  proposedTotal: number | null;
  proposedStatus: string | null;
  validUntil: string | null;
  sourceType: string;
  reason: string;
  anomalyFlags: string | null;
  status: string;
  submittedByName: string;
  submittedAt: string;
  decidedByName: string | null;
  decidedAt: string | null;
  decisionReason: string | null;
  canDecide: boolean;
}

export interface InventorySnapshot {
  snapshotId: number;
  inventoryKind: string;
  itemLabel: string;
  quantity: number | null;
  availableQuantity: number | null;
  capturedAt: string;
}
