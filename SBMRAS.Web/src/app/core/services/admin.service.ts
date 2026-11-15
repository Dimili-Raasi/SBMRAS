import { Injectable, inject } from '@angular/core';
import { Observable, map } from 'rxjs';

import {
  AdminFacility,
  AdminFacilityQuery,
  AdminPermission,
  AdminRole,
  AdminUser,
  AdminUserQuery,
  FacilityAssignmentSave,
  FacilityDecision,
  FacilitySave,
  MasterDataRow,
  MasterDataType,
  SettingUpdate,
  SystemSetting,
  UserSave,
} from '../models/admin.models';
import { PagedResult } from '../models/api.models';
import { ApiService } from './api.service';

/** Administration endpoints (contract §6 Admin). */
@Injectable({ providedIn: 'root' })
export class AdminService {
  private readonly api = inject(ApiService);

  // Users
  getUsers(query: AdminUserQuery): Observable<PagedResult<AdminUser>> {
    return this.api
      .get<PagedResult<AdminUser>>('admin/users', query)
      .pipe(map((page) => ({ ...page, items: (page.items ?? []).map(normalizeUser) })));
  }

  getUser(userId: number): Observable<AdminUser> {
    return this.api.get<AdminUser>(`admin/users/${userId}`).pipe(map(normalizeUser));
  }

  createUser(body: UserSave): Observable<AdminUser> {
    return this.api.post<AdminUser>('admin/users', body).pipe(map(normalizeUser));
  }

  updateUser(userId: number, body: UserSave): Observable<AdminUser> {
    return this.api.put<AdminUser>(`admin/users/${userId}`, body).pipe(map(normalizeUser));
  }

  setUserStatus(userId: number, isActive: boolean): Observable<AdminUser> {
    return this.api.post<AdminUser>(`admin/users/${userId}/status`, { isActive }).pipe(map(normalizeUser));
  }

  setUserFacilities(userId: number, assignments: FacilityAssignmentSave[]): Observable<AdminUser> {
    return this.api
      .put<AdminUser>(`admin/users/${userId}/facilities`, { assignments })
      .pipe(map(normalizeUser));
  }

  // Roles & permissions
  getRoles(): Observable<AdminRole[]> {
    return this.api
      .get<AdminRole[]>('admin/roles')
      .pipe(map((roles) => (roles ?? []).map((r) => ({ ...r, permissionCodes: toArray(r.permissionCodes) }))));
  }

  getPermissions(): Observable<AdminPermission[]> {
    return this.api.get<AdminPermission[]>('admin/permissions').pipe(map((p) => p ?? []));
  }

  updateRolePermissions(roleId: number, permissionCodes: string[]): Observable<unknown> {
    return this.api.put<unknown>(`admin/roles/${roleId}/permissions`, { permissionCodes });
  }

  // Facilities
  getFacilities(query: AdminFacilityQuery): Observable<PagedResult<AdminFacility>> {
    return this.api.get<PagedResult<AdminFacility>>('admin/facilities', query);
  }

  createFacility(body: FacilitySave): Observable<AdminFacility> {
    return this.api.post<AdminFacility>('admin/facilities', body);
  }

  updateFacility(facilityId: number, body: FacilitySave): Observable<AdminFacility> {
    return this.api.put<AdminFacility>(`admin/facilities/${facilityId}`, body);
  }

  verifyFacility(facilityId: number, decision: FacilityDecision, notes: string | null): Observable<AdminFacility> {
    return this.api.post<AdminFacility>(`admin/facilities/${facilityId}/verify`, { decision, notes });
  }

  // Master data
  getMasterData(type: MasterDataType): Observable<MasterDataRow[]> {
    return this.api.get<MasterDataRow[]>(`admin/master-data/${type}`).pipe(map((rows) => rows ?? []));
  }

  saveMasterData(type: MasterDataType, body: Record<string, unknown>): Observable<MasterDataRow> {
    return this.api.post<MasterDataRow>(`admin/master-data/${type}`, body);
  }

  /** Lightweight facility options for assignment pickers (all statuses, first 100 by status/name). */
  getFacilityOptions(search?: string | null): Observable<AdminFacility[]> {
    return this.getFacilities({ search: search || null, page: 1, pageSize: 100 }).pipe(map((p) => p.items ?? []));
  }

  // Settings
  getSettings(): Observable<SystemSetting[]> {
    return this.api.get<SystemSetting[]>('admin/settings').pipe(map((s) => s ?? []));
  }

  updateSettings(settings: SettingUpdate[]): Observable<SystemSetting[]> {
    return this.api.put<SystemSetting[]>('admin/settings', { settings });
  }
}

function toArray(value: unknown): string[] {
  if (Array.isArray(value)) {
    return value.map(String);
  }
  if (typeof value === 'string') {
    return value
      .split(',')
      .map((v) => v.trim())
      .filter(Boolean);
  }
  return [];
}

function normalizeUser(user: AdminUser): AdminUser {
  return {
    ...user,
    roleCodes: toArray(user.roleCodes),
    roleNames: toArray(user.roleNames),
    roleSources: user.roleSources ?? [],
    facilities: user.facilities ?? [],
  };
}
