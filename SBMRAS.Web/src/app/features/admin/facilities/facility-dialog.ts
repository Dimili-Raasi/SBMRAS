import { ChangeDetectionStrategy, Component, OnInit, inject, signal } from '@angular/core';
import { FormControl, FormGroup, ReactiveFormsModule, Validators } from '@angular/forms';
import { MatButtonModule } from '@angular/material/button';
import { MAT_DIALOG_DATA, MatDialogModule, MatDialogRef } from '@angular/material/dialog';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatIconModule } from '@angular/material/icon';
import { MatInputModule } from '@angular/material/input';
import { MatProgressBarModule } from '@angular/material/progress-bar';
import { MatSelectModule } from '@angular/material/select';
import { MatSlideToggleModule } from '@angular/material/slide-toggle';

import { AdminFacility, FacilitySave, FacilityType } from '../../../core/models/admin.models';
import { AreaLookup } from '../../../core/models/lookup.models';
import { AdminService } from '../../../core/services/admin.service';
import { LookupService } from '../../../core/services/lookup.service';
import { UiService } from '../../../core/services/ui.service';
import { isConflict, serverErrorText } from '../admin-shared';

export interface FacilityDialogData {
  facility: AdminFacility | null;
}

@Component({
  selector: 'sb-facility-dialog',
  imports: [
    ReactiveFormsModule,
    MatButtonModule,
    MatDialogModule,
    MatFormFieldModule,
    MatIconModule,
    MatInputModule,
    MatProgressBarModule,
    MatSelectModule,
    MatSlideToggleModule,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './facility-dialog.html',
  styleUrl: '../admin.scss',
})
export class FacilityDialog implements OnInit {
  private readonly admin = inject(AdminService);
  private readonly lookups = inject(LookupService);
  private readonly ui = inject(UiService);
  private readonly ref = inject<MatDialogRef<FacilityDialog, boolean>>(MatDialogRef);
  protected readonly data = inject<FacilityDialogData>(MAT_DIALOG_DATA);

  protected readonly facility = this.data.facility;
  protected readonly isNew = !this.facility;
  protected readonly areas = signal<AreaLookup[]>([]);
  protected readonly saving = signal(false);
  protected readonly formError = signal('');
  protected readonly conflict = signal(false);

  protected readonly form = new FormGroup({
    facilityType: new FormControl<FacilityType>(this.facility?.facilityType ?? 'Hospital', {
      nonNullable: true,
      validators: Validators.required,
    }),
    name: new FormControl(this.facility?.name ?? '', {
      nonNullable: true,
      validators: [Validators.required, Validators.maxLength(200)],
    }),
    licenseNo: new FormControl(this.facility?.licenseNo ?? '', { nonNullable: true, validators: Validators.maxLength(60) }),
    addressLine: new FormControl(this.facility?.addressLine ?? '', {
      nonNullable: true,
      validators: [Validators.required, Validators.maxLength(300)],
    }),
    areaId: new FormControl<number | null>(this.facility?.areaId ?? null, Validators.required),
    city: new FormControl(this.facility?.city ?? '', { nonNullable: true, validators: Validators.maxLength(100) }),
    pincode: new FormControl(this.facility?.pincode ?? '', {
      nonNullable: true,
      validators: [Validators.pattern(/^[0-9]{6}$/)],
    }),
    latitude: new FormControl<number | null>(this.facility?.latitude ?? null, [Validators.min(-90), Validators.max(90)]),
    longitude: new FormControl<number | null>(this.facility?.longitude ?? null, [
      Validators.min(-180),
      Validators.max(180),
    ]),
    contactPhone: new FormControl(this.facility?.contactPhone ?? '', {
      nonNullable: true,
      validators: [Validators.required, Validators.maxLength(30), Validators.pattern(/^[+0-9 ()-]+$/)],
    }),
    contactEmail: new FormControl(this.facility?.contactEmail ?? '', {
      nonNullable: true,
      validators: [Validators.email, Validators.maxLength(320)],
    }),
    is24x7: new FormControl(this.facility?.is24x7 ?? false, { nonNullable: true }),
    isActive: new FormControl(this.facility?.isActive ?? true, { nonNullable: true }),
  });

  ngOnInit(): void {
    this.lookups.load().subscribe({
      next: (l) => this.areas.set(l.areas ?? []),
      error: () => this.formError.set('Areas could not be loaded. Close the dialog and try again.'),
    });
    this.form.controls.areaId.valueChanges.subscribe((id) => {
      const area = this.areas().find((a) => a.areaId === id);
      if (area && !this.form.controls.city.value) {
        this.form.controls.city.setValue(area.city);
      }
    });
  }

  protected async save(): Promise<void> {
    this.formError.set('');
    this.conflict.set(false);
    if (this.form.invalid) {
      this.form.markAllAsTouched();
      this.formError.set('Fix the highlighted fields and try again.');
      return;
    }
    const v = this.form.getRawValue();
    if (!this.isNew && this.facility!.isActive && !v.isActive) {
      const ok = await this.ui.confirm({
        title: 'Deactivate facility?',
        message: `${v.name} will be hidden from public search and users cannot be newly assigned to it.`,
        confirmText: 'Deactivate',
        danger: true,
      });
      if (!ok) {
        return;
      }
    }
    const body: FacilitySave = {
      facilityType: v.facilityType,
      name: v.name.trim(),
      licenseNo: v.licenseNo.trim() || null,
      addressLine: v.addressLine.trim(),
      areaId: v.areaId!,
      city: v.city.trim() || null,
      pincode: v.pincode.trim() || null,
      latitude: v.latitude === null || (v.latitude as unknown) === '' ? null : Number(v.latitude),
      longitude: v.longitude === null || (v.longitude as unknown) === '' ? null : Number(v.longitude),
      contactPhone: v.contactPhone.trim(),
      contactEmail: v.contactEmail.trim() || null,
      is24x7: v.is24x7,
    };
    if (!this.isNew) {
      body.isActive = v.isActive;
      body.rowVersion = this.facility!.rowVersion;
    }
    this.saving.set(true);
    const call = this.isNew
      ? this.admin.createFacility(body)
      : this.admin.updateFacility(this.facility!.facilityId, body);
    call.subscribe({
      next: (saved) => {
        this.saving.set(false);
        this.ui.success(
          this.isNew ? `${saved?.facilityCode ?? 'Facility'} registered (Pending verification).` : 'Facility updated.',
        );
        this.ref.close(true);
      },
      error: (err) => {
        this.saving.set(false);
        this.conflict.set(isConflict(err) && !this.isNew);
        this.formError.set(serverErrorText(err));
      },
    });
  }

  protected async close(): Promise<void> {
    if (this.form.dirty) {
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
    this.ref.close(false);
  }

  /** After a concurrency conflict, close so the list reloads the latest row version. */
  protected reloadLatest(): void {
    this.ref.close(true);
  }
}
