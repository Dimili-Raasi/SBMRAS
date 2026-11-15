/** Administration models (contract §6 Admin). */

export type RoleSource = 'Local' | 'Entra';
export type AssignmentRole = 'Manager' | 'Operator' | 'Verifier';
export const ASSIGNMENT_ROLES: AssignmentRole[] = ['Manager', 'Operator', 'Verifier'];

export interface UserRoleSource {
  roleCode: string;
  source: RoleSource;
}

export interface UserFacilityAssignment {
  facilityId: number;
  facilityCode?: string | null;
  name: string;
  facilityType: FacilityType;
  assignmentRole: AssignmentRole;
}

export interface AdminUser {
  userId: number;
  displayName: string;
  givenName: string | null;
  familyName: string | null;
  email: string | null;
  phone: string | null;
  organizationName: string | null;
  areaId: number | null;
  areaName: string | null;
  roleCodes: string[];
  roleNames: string[];
  roleSources?: UserRoleSource[];
  isActive: boolean;
  isSelfRegistered: boolean;
  entraLinked: boolean;
  lastLoginAt: string | null;
  createdAt: string;
  facilityCount?: number;
  facilities?: UserFacilityAssignment[];
}

export interface AdminUserQuery {
  search?: string | null;
  roleCode?: string | null;
  isActive?: boolean | null;
  page: number;
  pageSize: number;
}

export interface UserSave {
  displayName: string;
  givenName: string | null;
  familyName: string | null;
  email: string;
  phone: string | null;
  organizationName: string | null;
  areaId: number | null;
  /** Local roles only; Entra-sourced roles are managed by Microsoft Entra. */
  roleCodes: string[];
  isActive: boolean;
}

export interface FacilityAssignmentSave {
  facilityId: number;
  assignmentRole: AssignmentRole;
}

export interface AdminRole {
  roleId: number;
  roleCode: string;
  roleName: string;
  description: string | null;
  entraAppRole: string | null;
  entraGroupName: string | null;
  isSystem?: boolean;
  isActive?: boolean;
  userCount: number;
  permissionCodes: string[];
}

export interface AdminPermission {
  permissionId: number;
  permissionCode: string;
  permissionName: string;
  module: string;
  description: string | null;
}

export type FacilityType = 'Hospital' | 'BloodBank';
export type FacilityVerificationStatus = 'Pending' | 'Verified' | 'Rejected' | 'Suspended';
export type FacilityDecision = 'Verify' | 'Reject' | 'Suspend' | 'Reactivate';

export interface AdminFacility {
  facilityId: number;
  facilityCode: string;
  name: string;
  facilityType: FacilityType;
  licenseNo: string | null;
  addressLine: string;
  areaId: number;
  areaName: string | null;
  city: string | null;
  pincode: string | null;
  latitude: number | null;
  longitude: number | null;
  contactPhone: string;
  contactEmail: string | null;
  is24x7: boolean;
  verificationStatus: FacilityVerificationStatus;
  verifiedAt: string | null;
  verifiedByName?: string | null;
  verificationNotes: string | null;
  isActive: boolean;
  qualityScore: number | null;
  freshPercent: number | null;
  staleRecords: number | null;
  lastUpdateAt: string | null;
  assignedUsers?: number;
  rowVersion: string | null;
  createdAt: string;
}

export interface AdminFacilityQuery {
  status?: string | null;
  facilityType?: string | null;
  search?: string | null;
  page: number;
  pageSize: number;
}

export interface FacilitySave {
  facilityType: FacilityType;
  name: string;
  licenseNo: string | null;
  addressLine: string;
  areaId: number;
  city: string | null;
  pincode: string | null;
  latitude: number | null;
  longitude: number | null;
  contactPhone: string;
  contactEmail: string | null;
  is24x7: boolean;
  isActive?: boolean;
  rowVersion?: string | null;
}

/** Allowed decisions per verification status (mirrors usp_Facility_Verify). */
export const FACILITY_DECISIONS: Record<FacilityVerificationStatus, FacilityDecision[]> = {
  Pending: ['Verify', 'Reject'],
  Rejected: ['Verify'],
  Verified: ['Suspend'],
  Suspended: ['Reactivate'],
};

export type MasterDataType = 'areas' | 'components' | 'units' | 'resource-categories' | 'resource-types';

export interface MasterDataRow {
  id: number;
  name: string;
  isActive: boolean;
  code?: string | null;
  city?: string | null;
  state?: string | null;
  pincode?: string | null;
  shelfLifeDays?: number | null;
  storageNote?: string | null;
  description?: string | null;
  categoryId?: number | null;
  categoryName?: string | null;
  defaultUnitId?: number | null;
  unitCode?: string | null;
  trackingMode?: 'Count' | 'Status' | 'Capacity' | null;
  [key: string]: unknown;
}

export type SettingDataType = 'int' | 'decimal' | 'bool' | 'string';

export interface SystemSetting {
  settingKey: string;
  settingValue: string;
  dataType: SettingDataType;
  category: string;
  description: string | null;
  updatedAt: string | null;
  updatedByName: string | null;
}

export interface SettingUpdate {
  settingKey: string;
  settingValue: string;
}
