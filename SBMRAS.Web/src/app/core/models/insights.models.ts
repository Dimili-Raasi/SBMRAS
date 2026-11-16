import { PagedResult } from './api.models';

export interface DashboardSummary {
  role: string | null;
  totalFacilities: number | null;
  verifiedFacilities: number | null;
  bloodUnitsAvailable: number | null;
  freshPercent: number | null;
  staleRecords: number | null;
  pendingReviews: number | null;
  openRequests: number | null;
  emergencyRequests: number | null;
  fulfilledRequests: number | null;
  myOpenRequests: number | null;
  openIssues: number | null;
  avgQualityScore: number | null;
  pendingFacilityVerifications: number | null;
}

export interface DashboardChartPoint {
  label: string;
  value: number | null;
}

export interface RequestTrendPoint {
  label: string;
  submitted: number | null;
  fulfilled: number | null;
}

export interface ResourceUtilizationPoint {
  label: string;
  total: number | null;
  available: number | null;
}

export interface DashboardCharts {
  bloodByGroup: DashboardChartPoint[];
  freshness: DashboardChartPoint[];
  requestTrend: RequestTrendPoint[];
  requestStatus: DashboardChartPoint[];
  resourceUtilization: ResourceUtilizationPoint[];
  qualityByFacility: DashboardChartPoint[];
}

export interface DashboardWorklistItem {
  type: string;
  referenceNo: string | null;
  title: string;
  status: string | null;
  priority: string | null;
  dueAt: string | null;
  route: string | null;
}

export interface DashboardActivityItem {
  auditId: number;
  entityType: string;
  entityId: string | number;
  referenceNo: string | null;
  action: string;
  description: string;
  userName: string | null;
  createdAt: string;
}

export interface ReportDefinition {
  code: string;
  name: string;
  description: string | null;
}

export interface ReportFacilityOption {
  facilityId: number;
  facilityCode: string;
  name: string;
  facilityType: string;
}

export type ReportColumnType = 'text' | 'number' | 'date' | 'percent';

export interface ReportColumn {
  key: string;
  label: string;
  type: ReportColumnType;
}

export interface ReportChartDataset {
  label: string;
  data: number[];
}

export interface ReportChart {
  type: 'bar' | 'line' | 'doughnut';
  labels: string[];
  datasets: ReportChartDataset[];
}

export interface ReportResult {
  code: string;
  name: string;
  columns: ReportColumn[];
  rows: Record<string, string | number | null>[];
  chart: ReportChart | null;
}

export interface ReportQuery {
  fromDate?: string | null;
  toDate?: string | null;
  facilityId?: number | null;
  areaId?: number | null;
}

export interface AuditLog {
  auditId: number;
  entityType: string;
  entityId: string | number;
  referenceNo: string | null;
  facilityId: number | null;
  facilityName: string | null;
  action: string;
  description: string;
  oldValues: string | null;
  newValues: string | null;
  sourceType: string | null;
  reason: string | null;
  correlationId: string | null;
  userName: string | null;
  actorRole: string | null;
  createdAt: string;
}

export interface AuditLogQuery {
  search?: string | null;
  entityType?: string | null;
  action?: string | null;
  facilityId?: number | null;
  userId?: number | null;
  correlationId?: string | null;
  fromDate?: string | null;
  toDate?: string | null;
  page: number;
  pageSize: number;
}

export type PagedAuditLogs = PagedResult<AuditLog>;

