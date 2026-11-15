export type ChangeStatus = 'Applied' | 'PendingReview' | 'Rejected';
export type ChangeDecision = 'Approve' | 'Reject';

export interface InventoryChange {
  changeId: number;
  changeNo: string;
  facilityId: number;
  facilityName: string;
  inventoryKind: 'Blood' | 'Resource';
  itemLabel: string;
  previousQuantity: number | null;
  proposedQuantity: number | null;
  previousAvailable: number | null;
  proposedAvailable: number | null;
  proposedTotal: number | null;
  proposedStatus: string | null;
  validUntil: string | null;
  sourceType: string | null;
  reason: string | null;
  anomalyFlags: string | null;
  status: ChangeStatus;
  submittedByName: string | null;
  submittedAt: string | null;
  decidedByName: string | null;
  decidedAt: string | null;
  decisionReason: string | null;
  canDecide: boolean;
  rowVersion?: string | null;
}

export interface InventoryChangeQuery {
  status?: string | null;
  facilityId?: number | null;
  inventoryKind?: string | null;
  page?: number;
  pageSize?: number;
}

export interface ChangeDecisionRequest {
  decision: ChangeDecision;
  reason: string;
}
