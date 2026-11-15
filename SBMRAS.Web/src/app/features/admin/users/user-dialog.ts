import { ChangeDetectionStrategy, Component, OnInit, computed, inject, signal } from '@angular/core';
import { DatePipe } from '@angular/common';
import { FormArray, FormControl, FormGroup, ReactiveFormsModule, Validators } from '@angular/forms';
import { MatButtonModule } from '@angular/material/button';
import { MatCheckboxModule } from '@angular/material/checkbox';
import { MAT_DIALOG_DATA, MatDialogModule, MatDialogRef } from '@angular/material/dialog';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatIconModule } from '@angular/material/icon';
import { MatInputModule } from '@angular/material/input';
import { MatProgressBarModule } from '@angular/material/progress-bar';
import { MatSelectModule } from '@angular/material/select';
import { MatTabsModule } from '@angular/material/tabs';
import { MatTooltipModule } from '@angular/material/tooltip';
import { forkJoin, of, catchError } from 'rxjs';

import {
  ASSIGNMENT_ROLES,
  AdminFacility,
  AdminUser,
  AssignmentRole,
  FacilityAssignmentSave,
  UserSave,
} from '../../../core/models/admin.models';
import { AreaLookup } from '../../../core/models/lookup.models';
import { Permissions } from '../../../core/models/permissions';
import { AdminService } from '../../../core/services/admin.service';
import { LookupService } from '../../../core/services/lookup.service';
import { SessionService } from '../../../core/services/session.service';
import { UiService } from '../../../core/services/ui.service';
import { errorMessage } from '../../../core/utils/api-error';
import { ADMIN_ROLE_OPTIONS, adminShared, serverErrorText } from '../admin-shared';

export interface UserDialogData {
  userId: number | null;
  tab?: number;
}

type AssignmentGroup = FormGroup<{
  facilityId: FormControl<number | null>;
  assignmentRole: FormControl<AssignmentRole>;
}>;

@Component({
  selector: 'sb-user-dialog',
  imports: [
    ...adminShared,
    DatePipe,
    ReactiveFormsModule,
    MatButtonModule,
    MatCheckboxModule,
    MatDialogModule,
    MatFormFieldModule,
    MatIconModule,
    MatInputModule,
    MatProgressBarModule,
    MatSelectModule,
    MatTabsModule,
    MatTooltipModule,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './user-dialog.html',
  styleUrl: '../admin.scss',
})
export class UserDialog implements OnInit {
  private readonly admin = inject(AdminService);
  private readonly lookups = inject(LookupService);
  private readonly session = inject(SessionService);
  private readonly ui = inject(UiService);
  private readonly ref = inject<MatDialogRef<UserDialog, boolean>>(MatDialogRef);
  protected readonly data = inject<UserDialogData>(MAT_DIALOG_DATA);

  protected readonly P = Permissions;
  protected readonly roleOptions = ADMIN_ROLE_OPTIONS;
  protected readonly assignmentRoles = ASSIGNMENT_ROLES;
  protected readonly isNew = this.data.userId === null;

  protected readonly loading = signal(!this.isNew);
  protected readonly loadError = signal('');
  protected readonly saving = signal(false);
  protected readonly formError = signal('');
  protected readonly assignError = signal('');
  protected readonly user = signal<AdminUser | null>(null);
  protected readonly areas = signal<AreaLookup[]>([]);
  protected readonly facilities = signal<AdminFacility[]>([]);
  protected readonly facilitiesError = signal('');
  protected readonly tab = signal(this.isNew ? 0 : (this.data.tab ?? 0));
  private changed = false;

  protected readonly entraRoles = computed(() =>
    (this.user()?.roleSources ?? []).filter((r) => r.source === 'Entra').map((r) => r.roleCode),
  );
  protected readonly isSelf = computed(() => this.user()?.userId === this.session.user()?.userId);
  protected readonly heldRoles = computed(() => {
    const local = this.localRoles();
    return new Set<string>([...this.entraRoles(), ...local, 'PublicUser']);
  });
  protected readonly localRoles = signal<string[]>([]);

  protected readonly form = new FormGroup({
    displayName: new FormControl('', { nonNullable: true, validators: [Validators.required, Validators.maxLength(150)] }),
    givenName: new FormControl('', { nonNullable: true, validators: [Validators.maxLength(100)] }),
    familyName: new FormControl('', { nonNullable: true, validators: [Validators.maxLength(100)] }),
    email: new FormControl('', {
      nonNullable: true,
      validators: [Validators.required, Validators.email, Validators.maxLength(320)],
    }),
    phone: new FormControl('', {
      nonNullable: true,
      validators: [Validators.maxLength(30), Validators.pattern(/^[+0-9 ()-]*$/)],
    }),
    organizationName: new FormControl('', { nonNullable: true, validators: [Validators.maxLength(200)] }),
    areaId: new FormControl<number | null>(null),
  });

  protected readonly assignments = new FormArray<AssignmentGroup>([]);

  ngOnInit(): void {
    this.lookups.load().subscribe({
      next: (l) => this.areas.set(l.areas ?? []),
      error: () => this.areas.set([]),
    });
    if (!this.isNew) {
      this.load();
    }
  }

  protected load(): void {
    this.loading.set(true);
    this.loadError.set('');
    forkJoin({
      user: this.admin.getUser(this.data.userId!),
      facilities: this.admin.getFacilityOptions().pipe(
        catchError((err) => {
          this.facilitiesError.set(`Facility list unavailable: ${errorMessage(err)}`);
          return of([] as AdminFacility[]);
        }),
      ),
    }).subscribe({
      next: ({ user, facilities }) => {
        this.facilities.set(facilities);
        this.applyUser(user);
        this.loading.set(false);
      },
      error: (err) => {
        this.loadError.set(errorMessage(err));
        this.loading.set(false);
      },
    });
  }

  private applyUser(user: AdminUser): void {
    this.user.set(user);
    this.form.reset({
      displayName: user.displayName ?? '',
      givenName: user.givenName ?? '',
      familyName: user.familyName ?? '',
      email: user.email ?? '',
      phone: user.phone ?? '',
      organizationName: user.organizationName ?? '',
      areaId: user.areaId ?? null,
    });
    this.localRoles.set(
      (user.roleSources ?? []).filter((r) => r.source === 'Local').map((r) => r.roleCode),
    );
    this.assignments.clear();
    for (const f of user.facilities ?? []) {
      this.assignments.push(this.assignmentGroup(f.facilityId, f.assignmentRole));
    }
    this.assignments.markAsPristine();
  }

  private assignmentGroup(facilityId: number | null, role: AssignmentRole): AssignmentGroup {
    return new FormGroup({
      facilityId: new FormControl<number | null>(facilityId, Validators.required),
      assignmentRole: new FormControl<AssignmentRole>(role, { nonNullable: true, validators: Validators.required }),
    });
  }

  // Roles
  protected isEntra(code: string): boolean {
    return this.entraRoles().includes(code);
  }

  protected isLocal(code: string): boolean {
    return this.localRoles().includes(code);
  }

  protected roleLocked(code: string): boolean {
    return code === 'PublicUser' || (this.isSelf() && code === 'Admin' && this.isLocal(code) && !this.isEntra(code));
  }

  protected toggleRole(code: string, checked: boolean): void {
    this.localRoles.update((roles) => (checked ? [...new Set([...roles, code])] : roles.filter((r) => r !== code)));
    this.form.markAsDirty();
  }

  // Profile save
  protected async save(): Promise<void> {
    this.formError.set('');
    if (this.form.invalid) {
      this.form.markAllAsTouched();
      this.formError.set('Fix the highlighted fields and try again.');
      return;
    }
    const v = this.form.getRawValue();
    const removingAdmin = !this.isNew && this.user()?.roleCodes.includes('Admin') && !this.heldRoles().has('Admin');
    if (removingAdmin) {
      const ok = await this.ui.confirm({
        title: 'Remove administrator role?',
        message: `${v.displayName} will lose all administration permissions.`,
        confirmText: 'Remove role',
        danger: true,
      });
      if (!ok) {
        return;
      }
    }
    const body: UserSave = {
      displayName: v.displayName.trim(),
      givenName: v.givenName.trim() || null,
      familyName: v.familyName.trim() || null,
      email: v.email.trim().toLowerCase(),
      phone: v.phone.trim() || null,
      organizationName: v.organizationName.trim() || null,
      areaId: v.areaId,
      roleCodes: [...new Set(['PublicUser', ...this.localRoles()])],
      isActive: this.user()?.isActive ?? true,
    };
    this.saving.set(true);
    const call = this.isNew ? this.admin.createUser(body) : this.admin.updateUser(this.user()!.userId, body);
    call.subscribe({
      next: (saved) => {
        this.saving.set(false);
        this.changed = true;
        this.ui.success(this.isNew ? 'User created. They can sign in with this e-mail address.' : 'User updated.');
        if (this.isNew) {
          this.ref.close(true);
        } else {
          this.applyUser(saved);
        }
      },
      error: (err) => {
        this.saving.set(false);
        this.formError.set(serverErrorText(err));
      },
    });
  }

  protected async toggleStatus(): Promise<void> {
    const u = this.user();
    if (!u) {
      return;
    }
    const activate = !u.isActive;
    const ok = await this.ui.confirm({
      title: activate ? 'Activate user?' : 'Deactivate user?',
      message: activate
        ? `${u.displayName} will be able to sign in again.`
        : `${u.displayName} will be signed out of SBMRAS and blocked from signing in. Facility assignments are kept.`,
      confirmText: activate ? 'Activate' : 'Deactivate',
      danger: !activate,
    });
    if (!ok) {
      return;
    }
    this.saving.set(true);
    this.formError.set('');
    this.admin.setUserStatus(u.userId, activate).subscribe({
      next: (saved) => {
        this.saving.set(false);
        this.changed = true;
        this.applyUser(saved);
        this.ui.success(activate ? 'User activated.' : 'User deactivated.');
      },
      error: (err) => {
        this.saving.set(false);
        this.formError.set(serverErrorText(err));
      },
    });
  }

  // Facility assignments
  protected addAssignment(): void {
    this.assignments.push(this.assignmentGroup(null, 'Operator'));
    this.assignments.markAsDirty();
  }

  protected removeAssignment(index: number): void {
    this.assignments.removeAt(index);
    this.assignments.markAsDirty();
  }

  protected facilityOptionsFor(index: number): AdminFacility[] {
    const taken = new Set(
      this.assignments.controls.filter((_, i) => i !== index).map((c) => c.controls.facilityId.value),
    );
    const current = this.assignments.at(index).controls.facilityId.value;
    return this.facilities().filter(
      (f) => !taken.has(f.facilityId) && (f.isActive || f.facilityId === current),
    );
  }

  protected facilityById(id: number | null): AdminFacility | undefined {
    return this.facilities().find((f) => f.facilityId === id);
  }

  protected roleWarning(id: number | null): string {
    const f = this.facilityById(id);
    const held = this.user()?.roleCodes ?? [];
    if (!f || held.includes('Admin')) {
      return '';
    }
    if (f.facilityType === 'Hospital' && !held.includes('HospitalManagement')) {
      return 'Requires the Hospital Management role.';
    }
    if (f.facilityType === 'BloodBank' && !held.includes('BloodBank')) {
      return 'Requires the Blood Bank role.';
    }
    return '';
  }

  protected async saveAssignments(): Promise<void> {
    this.assignError.set('');
    if (this.assignments.invalid) {
      this.assignments.markAllAsTouched();
      this.assignError.set('Select a facility and role for every row.');
      return;
    }
    const rows: FacilityAssignmentSave[] = this.assignments.controls.map((c) => ({
      facilityId: c.controls.facilityId.value!,
      assignmentRole: c.controls.assignmentRole.value,
    }));
    if (new Set(rows.map((r) => r.facilityId)).size !== rows.length) {
      this.assignError.set('A facility can only be assigned once per user.');
      return;
    }
    const removed = (this.user()?.facilities ?? []).filter((f) => !rows.some((r) => r.facilityId === f.facilityId));
    if (removed.length) {
      const ok = await this.ui.confirm({
        title: 'Remove facility access?',
        message: `Access to ${removed.map((f) => f.name).join(', ')} will be ended for this user.`,
        confirmText: 'Save assignments',
        danger: true,
      });
      if (!ok) {
        return;
      }
    }
    this.saving.set(true);
    this.admin.setUserFacilities(this.user()!.userId, rows).subscribe({
      next: (saved) => {
        this.saving.set(false);
        this.changed = true;
        this.applyUser(saved);
        this.ui.success('Facility assignments saved.');
      },
      error: (err) => {
        this.saving.set(false);
        this.assignError.set(serverErrorText(err));
      },
    });
  }

  protected async close(): Promise<void> {
    if (this.form.dirty || this.assignments.dirty) {
      const ok = await this.ui.confirm({
        title: 'Discard changes?',
        message: 'You have unsaved changes that will be lost.',
        confirmText: 'Discard',
        danger: true,
      });
      if (!ok) {
        return;
      }
    }
    this.ref.close(this.changed);
  }
}
