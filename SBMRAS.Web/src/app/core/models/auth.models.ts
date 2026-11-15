export type AuthMode = 'DevHeader' | 'EntraId';

export interface AuthConfig {
  mode: AuthMode;
  instance?: string | null;
  tenantId?: string | null;
  spaClientId?: string | null;
  apiScope?: string | null;
  authority?: string | null;
  userFlow?: string | null;
  knownAuthority?: string | null;
}

export interface DevUser {
  userId: number;
  displayName: string;
  email: string | null;
  roleCode: string;
  roleName: string;
  organizationName: string | null;
  areaName: string | null;
  facilityNames: string | null;
}

export interface UserFacility {
  facilityId: number;
  facilityCode: string;
  name: string;
  facilityType: 'Hospital' | 'BloodBank';
  assignmentRole: 'Manager' | 'Operator' | 'Verifier';
}

export interface CurrentUser {
  userId: number;
  displayName: string;
  givenName: string | null;
  familyName: string | null;
  email: string | null;
  phone: string | null;
  organizationName: string | null;
  areaId: number | null;
  areaName: string | null;
  roles: string[];
  roleNames: string[];
  primaryRole: string;
  permissions: string[];
  facilities: UserFacility[];
}

export interface MenuItem {
  code: string;
  label: string;
  icon: string;
  route: string;
  sortOrder: number;
}

export interface MenuSection {
  section: string;
  sectionOrder: number;
  items: MenuItem[];
}
