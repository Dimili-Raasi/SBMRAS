export type InventoryKind = 'Blood' | 'Resource';
export type ImportBatchStatus = 'Validated' | 'Committed' | 'Cancelled';
export type ImportRowStatus = 'Valid' | 'Invalid' | 'Duplicate' | 'Applied' | 'Review';

export interface ImportBatch {
  batchId: number;
  batchNo: string;
  facilityId: number;
  facilityName: string;
  inventoryKind: InventoryKind;
  fileName: string;
  fileHash: string;
  totalRows: number | null;
  validRows: number | null;
  invalidRows: number | null;
  duplicateRows: number | null;
  reviewRows: number | null;
  appliedRows: number | null;
  status: ImportBatchStatus;
  submittedByName: string | null;
  submittedAt: string | null;
  committedByName: string | null;
  committedAt: string | null;
}

export interface ImportRow {
  importRowId: number;
  rowNumber: number;
  rawData: string | null;
  componentCode: string | null;
  aboGroup: string | null;
  rhFactor: string | null;
  resourceTypeCode: string | null;
  quantity: number | null;
  totalQuantity: number | null;
  availableQuantity: number | null;
  operationalStatus: string | null;
  earliestExpiryDate: string | null;
  validUntil: string | null;
  validationStatus: ImportRowStatus;
  errorCodes: string | null;
  errorMessages: string | null;
}

export interface ImportBatchDetail extends ImportBatch {
  rows: ImportRow[];
}

/** Row posted to `POST imports` (parsed in the browser). */
export interface ImportRowInput {
  rowNumber: number;
  rawData: string;
  componentCode: string | null;
  aboGroup: string | null;
  rhFactor: string | null;
  resourceTypeCode: string | null;
  quantity: number | null;
  totalQuantity: number | null;
  availableQuantity: number | null;
  operationalStatus: string | null;
  earliestExpiryDate: string | null;
  validUntil: string | null;
}

export interface ImportBatchCreate {
  facilityId: number;
  inventoryKind: InventoryKind;
  fileName: string;
  fileHash: string;
  rows: ImportRowInput[];
}

export interface ImportBatchQuery {
  facilityId?: number | null;
  status?: string | null;
  page?: number;
  pageSize?: number;
}

export interface ImportFacilityOption {
  facilityId: number;
  facilityCode: string;
  name: string;
  facilityType: 'Hospital' | 'BloodBank';
  verificationStatus?: string;
}

/** Hospitals import medical resources; blood banks import blood stock. */
export function kindForFacility(facilityType: string | null | undefined): InventoryKind | null {
  return facilityType === 'Hospital' ? 'Resource' : facilityType === 'BloodBank' ? 'Blood' : null;
}

export const IMPORT_TEMPLATES: Record<InventoryKind, string[]> = {
  Blood: ['componentCode', 'aboGroup', 'rhFactor', 'quantity', 'earliestExpiryDate', 'validUntil'],
  Resource: ['resourceTypeCode', 'totalQuantity', 'availableQuantity', 'operationalStatus', 'validUntil'],
};
