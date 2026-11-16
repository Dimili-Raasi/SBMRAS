export type RequestStatus =
  | 'Submitted'
  | 'UnderReview'
  | 'Matched'
  | 'Contacted'
  | 'Fulfilled'
  | 'UnableToFulfil'
  | 'Closed'
  | 'Cancelled';

export type RequestUrgency = 'Routine' | 'Urgent' | 'Emergency';

export const REQUEST_STATUSES: RequestStatus[] = [
  'Submitted',
  'UnderReview',
  'Matched',
  'Contacted',
  'Fulfilled',
  'UnableToFulfil',
  'Closed',
  'Cancelled',
];

export const OPEN_REQUEST_STATUSES: RequestStatus[] = ['Submitted', 'UnderReview', 'Matched', 'Contacted', 'UnableToFulfil'];

export const REQUEST_URGENCIES: RequestUrgency[] = ['Routine', 'Urgent', 'Emergency'];

export const REQUEST_STATUS_LABELS: Record<string, string> = {
  Submitted: 'Submitted',
  UnderReview: 'Under review',
  Matched: 'Matched',
  Contacted: 'Contacted',
  Fulfilled: 'Fulfilled',
  UnableToFulfil: 'Unable to fulfil',
  Closed: 'Closed',
  Cancelled: 'Cancelled',
};

/** Contract §4.5 state machine (server is authoritative via allowedTransitions). */
export const REQUEST_TRANSITIONS: Record<RequestStatus, RequestStatus[]> = {
  Submitted: ['UnderReview', 'Cancelled'],
  UnderReview: ['Matched', 'UnableToFulfil', 'Cancelled'],
  Matched: ['Contacted', 'Closed', 'Cancelled'],
  Contacted: ['Fulfilled', 'UnableToFulfil', 'Closed'],
  UnableToFulfil: ['Submitted', 'Closed'],
  Fulfilled: ['Closed'],
  Closed: [],
  Cancelled: [],
};

/** Statuses from which the owner may cancel their own request. */
export const OWNER_CANCELLABLE_STATUSES: RequestStatus[] = ['Submitted', 'UnderReview'];

export interface BloodRequest {
  requestId: number;
  requestNo: string;
  requesterUserId: number;
  requesterName: string | null;
  patientReference: string | null;
  aboGroup: string;
  rhFactor: string;
  bloodGroup: string | null;
  componentId: number;
  componentCode: string | null;
  componentName: string | null;
  quantityRequested: number | null;
  unitId: number;
  unitCode: string | null;
  urgency: RequestUrgency;
  neededBy: string | null;
  areaId: number;
  areaName: string | null;
  hospitalName: string | null;
  preferredFacilityId: number | null;
  preferredFacilityName: string | null;
  matchedFacilityId: number | null;
  matchedFacilityName: string | null;
  matchedFacilityPhone: string | null;
  contactName: string | null;
  contactPhone: string | null;
  notes: string | null;
  status: RequestStatus;
  statusReason: string | null;
  isOwner: boolean;
  createdAt: string;
  updatedAt: string | null;
  rowVersion: string | null;
}

export interface BloodRequestHistory {
  historyId: number;
  fromStatus: RequestStatus | null;
  toStatus: RequestStatus;
  note: string | null;
  facilityName: string | null;
  changedByName: string | null;
  changedAt: string;
}

export interface BloodRequestDetail extends BloodRequest {
  history: BloodRequestHistory[];
  allowedTransitions: RequestStatus[];
}

export interface RequestSearchQuery {
  scope?: 'mine' | 'all';
  status?: string | null;
  urgency?: string | null;
  aboGroup?: string | null;
  areaId?: number | null;
  search?: string | null;
  page?: number;
  pageSize?: number;
}

export interface RequestSave {
  patientReference?: string | null;
  aboGroup: string;
  rhFactor: string;
  componentId: number;
  quantityRequested: number;
  unitId: number;
  urgency: RequestUrgency;
  neededBy: string;
  areaId: number;
  hospitalName: string;
  preferredFacilityId?: number | null;
  contactName: string;
  contactPhone: string;
  contactConsent: boolean;
  notes?: string | null;
}

export interface RequestStatusChange {
  toStatus: RequestStatus;
  note?: string | null;
  matchedFacilityId?: number | null;
  rowVersion?: string | null;
}

/** BloodAvailability row returned by GET requests/{id}/matches (contract §6). */
export interface RequestMatch {
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
