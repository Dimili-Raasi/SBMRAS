export interface QualityScores {
  qualityScore: number | null;
  completenessScore: number | null;
  recencyScore: number | null;
  verificationScore: number | null;
  anomalyScore: number | null;
  fresh: number | null;
  aging: number | null;
  stale: number | null;
  unknown: number | null;
  underReview: number | null;
  openIssues: number | null;
}

export interface FacilityQuality extends QualityScores {
  facilityId: number;
  facilityName: string;
  facilityType: 'Hospital' | 'BloodBank';
  lastUpdateAt: string | null;
}

export interface DataQualitySummary {
  overall: QualityScores | null;
  facilities: FacilityQuality[];
}

export type IssueSeverity = 'Low' | 'Medium' | 'High';
export type IssueStatus = 'Open' | 'Resolved' | 'Dismissed';

export interface ValidationIssue {
  issueId: number;
  facilityId: number;
  facilityName: string;
  entityType: string;
  entityId: string | number;
  issueCode: string;
  severity: IssueSeverity;
  observedValue: string | null;
  message: string;
  status: IssueStatus;
  detectedAt: string;
  resolvedByName: string | null;
  resolvedAt: string | null;
  resolution: string | null;
}

export interface IssueQuery {
  status?: string | null;
  severity?: string | null;
  issueCode?: string | null;
  facilityId?: number | null;
  page?: number;
  pageSize?: number;
}

export interface ResolveIssueRequest {
  resolution: string;
  dismiss: boolean;
}

export interface ScanResult {
  staleFound: number;
  expiringFound: number;
  missingFound: number;
  issuesCreated: number;
}

export const ISSUE_CODES = ['STALE', 'NEGATIVE', 'LARGE_JUMP', 'MISSING_FIELD', 'DUPLICATE', 'CONFLICT', 'EXPIRING'];
