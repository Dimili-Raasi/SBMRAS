import { ChangeDetectionStrategy, Component, OnInit, computed, inject, signal } from '@angular/core';
import { MatButtonModule } from '@angular/material/button';
import { MatCheckboxModule } from '@angular/material/checkbox';
import { MatIconModule } from '@angular/material/icon';
import { MatProgressBarModule } from '@angular/material/progress-bar';
import { MatTooltipModule } from '@angular/material/tooltip';
import { concatMap, forkJoin, from, toArray } from 'rxjs';

import { AdminPermission, AdminRole } from '../../../core/models/admin.models';
import { ViewState } from '../../../core/models/api.models';
import { Permissions } from '../../../core/models/permissions';
import { AdminService } from '../../../core/services/admin.service';
import { SessionService } from '../../../core/services/session.service';
import { UiService } from '../../../core/services/ui.service';
import { errorMessage } from '../../../core/utils/api-error';
import { adminShared, serverErrorText } from '../admin-shared';

interface PermissionGroup {
  module: string;
  permissions: AdminPermission[];
}

/** Permissions the Administrator role must always keep (usp_Admin_UpdateRolePermissions). */
const ADMIN_LOCKED = ['users.manage', 'roles.manage'];

@Component({
  selector: 'sb-admin-roles',
  imports: [...adminShared, MatButtonModule, MatCheckboxModule, MatIconModule, MatProgressBarModule, MatTooltipModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './admin-roles.html',
  styleUrl: '../admin.scss',
})
export class AdminRoles implements OnInit {
  private readonly admin = inject(AdminService);
  private readonly ui = inject(UiService);
  private readonly session = inject(SessionService);
  protected readonly hasManage = computed(() => this.session.hasPermission(Permissions.RolesManage));

  protected readonly P = Permissions;
  protected readonly state = signal<ViewState>('loading');
  protected readonly error = signal('');
  protected readonly saveError = signal('');
  protected readonly saving = signal(false);
  protected readonly roles = signal<AdminRole[]>([]);
  protected readonly permissions = signal<AdminPermission[]>([]);
  /** Working copy: roleId → set of permission codes. */
  protected readonly matrix = signal<Record<number, Set<string>>>({});
  private original: Record<number, string> = {};

  protected readonly groups = computed<PermissionGroup[]>(() => {
    const map = new Map<string, AdminPermission[]>();
    for (const p of this.permissions()) {
      const key = p.module || 'General';
      map.set(key, [...(map.get(key) ?? []), p]);
    }
    return [...map.entries()].map(([module, permissions]) => ({ module, permissions }));
  });

  protected readonly dirtyRoles = computed(() =>
    this.roles().filter((r) => this.key(this.matrix()[r.roleId]) !== this.original[r.roleId]),
  );

  ngOnInit(): void {
    this.load();
  }

  protected load(): void {
    this.state.set('loading');
    this.saveError.set('');
    forkJoin({ roles: this.admin.getRoles(), permissions: this.admin.getPermissions() }).subscribe({
      next: ({ roles, permissions }) => {
        this.roles.set(roles);
        this.permissions.set(permissions);
        this.resetMatrix(roles);
        this.state.set(roles.length && permissions.length ? 'ready' : 'empty');
      },
      error: (err) => {
        this.error.set(errorMessage(err));
        this.state.set('error');
      },
    });
  }

  private resetMatrix(roles: AdminRole[]): void {
    const m: Record<number, Set<string>> = {};
    this.original = {};
    for (const r of roles) {
      m[r.roleId] = new Set(r.permissionCodes);
      this.original[r.roleId] = this.key(m[r.roleId]);
    }
    this.matrix.set(m);
  }

  private key(set: Set<string> | undefined): string {
    return [...(set ?? [])].sort().join(',');
  }

  protected has(role: AdminRole, code: string): boolean {
    return this.matrix()[role.roleId]?.has(code) ?? false;
  }

  protected locked(role: AdminRole, code: string): boolean {
    return role.roleCode === 'Admin' && ADMIN_LOCKED.includes(code);
  }

  protected changedCell(role: AdminRole, code: string): boolean {
    return this.has(role, code) !== role.permissionCodes.includes(code);
  }

  protected toggle(role: AdminRole, code: string, checked: boolean): void {
    this.matrix.update((m) => {
      const next = new Set(m[role.roleId]);
      if (checked) {
        next.add(code);
      } else {
        next.delete(code);
      }
      return { ...m, [role.roleId]: next };
    });
  }

  protected toggleColumn(role: AdminRole, checked: boolean): void {
    this.matrix.update((m) => {
      const next = new Set(checked ? this.permissions().map((p) => p.permissionCode) : []);
      if (role.roleCode === 'Admin') {
        ADMIN_LOCKED.forEach((c) => next.add(c));
      }
      return { ...m, [role.roleId]: next };
    });
  }

  protected columnState(role: AdminRole): 'all' | 'some' | 'none' {
    const count = this.matrix()[role.roleId]?.size ?? 0;
    return count === 0 ? 'none' : count >= this.permissions().length ? 'all' : 'some';
  }

  protected discard(): void {
    this.resetMatrix(this.roles());
    this.saveError.set('');
  }

  protected async save(): Promise<void> {
    const dirty = this.dirtyRoles();
    if (!dirty.length) {
      return;
    }
    const ok = await this.ui.confirm({
      title: 'Save permission changes?',
      message: `Permissions will change for ${dirty.map((r) => r.roleName).join(', ')}. Affected users get the new permissions on their next request.`,
      confirmText: 'Save changes',
      danger: false,
    });
    if (!ok) {
      return;
    }
    this.saving.set(true);
    this.saveError.set('');
    from(dirty)
      .pipe(
        concatMap((r) => this.admin.updateRolePermissions(r.roleId, [...this.matrix()[r.roleId]].sort())),
        toArray(),
      )
      .subscribe({
        next: () => {
          this.saving.set(false);
          this.ui.success('Role permissions saved.');
          this.load();
        },
        error: (err) => {
          this.saving.set(false);
          this.saveError.set(serverErrorText(err));
        },
      });
  }
}
