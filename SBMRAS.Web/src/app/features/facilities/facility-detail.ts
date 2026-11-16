import { ChangeDetectionStrategy, Component, DestroyRef, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { FormControl, FormGroup, ReactiveFormsModule, Validators } from '@angular/forms';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { MatButtonModule } from '@angular/material/button';
import { MatCheckboxModule } from '@angular/material/checkbox';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatIconModule } from '@angular/material/icon';
import { MatInputModule } from '@angular/material/input';
import { MatSelectModule } from '@angular/material/select';
import { Subscription } from 'rxjs';

import { ViewState } from '../../core/models/api.models';
import { AreaLookup } from '../../core/models/lookup.models';
import { FacilityDetail as FacilityDetailModel, FacilityUpdate } from '../../core/models/operations.models';
import { Permissions } from '../../core/models/permissions';
import { LookupService } from '../../core/services/lookup.service';
import { OperationsService } from '../../core/services/operations.service';
import { UiService } from '../../core/services/ui.service';
import { errorMessage } from '../../core/utils/api-error';
import { HasPermissionDirective } from '../../core/directives/has-permission.directive';
import { PageHeader } from '../../shared/components/page-header';
import { QualityGauge } from '../../shared/components/quality-gauge';
import { StatePanel } from '../../shared/components/state-panel';
import { StatusChip } from '../../shared/components/status-chip';

@Component({
  selector: 'sb-facility-detail',
  standalone: true,
  imports: [
    CommonModule,
    ReactiveFormsModule,
    RouterLink,
    MatButtonModule,
    MatCheckboxModule,
    MatFormFieldModule,
    MatIconModule,
    MatInputModule,
    MatSelectModule,
    HasPermissionDirective,
    PageHeader,
    QualityGauge,
    StatePanel,
    StatusChip,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './facility-detail.html',
  styleUrl: './facility-detail.scss',
})
export class FacilityDetail implements OnInit {
  private readonly route = inject(ActivatedRoute);
  private readonly operations = inject(OperationsService);
  private readonly lookups = inject(LookupService);
  private readonly ui = inject(UiService);
  private readonly destroyRef = inject(DestroyRef);

  protected readonly P = Permissions;
  protected readonly state = signal<ViewState>('loading');
  protected readonly error = signal('');
  protected readonly facility = signal<FacilityDetailModel | null>(null);
  protected readonly areas = signal<AreaLookup[]>([]);
  protected readonly editing = signal(false);
  protected readonly saving = signal(false);
  protected readonly saveError = signal('');
  protected readonly saveConflict = signal(false);
  private facilityId = 0;
  private loadSub?: Subscription;

  protected readonly form = new FormGroup({
    name: new FormControl('', { nonNullable: true, validators: [Validators.required, Validators.maxLength(200)] }),
    licenseNo: new FormControl('', { nonNullable: true, validators: Validators.maxLength(100) }),
    addressLine: new FormControl('', { nonNullable: true, validators: [Validators.required, Validators.maxLength(300)] }),
    areaId: new FormControl<number | null>(null, Validators.required),
    city: new FormControl('', { nonNullable: true, validators: [Validators.required, Validators.maxLength(100)] }),
    pincode: new FormControl('', { nonNullable: true, validators: [Validators.required, Validators.pattern(/^\d{6}$/)] }),
    latitude: new FormControl<number | null>(null, [Validators.min(-90), Validators.max(90)]),
    longitude: new FormControl<number | null>(null, [Validators.min(-180), Validators.max(180)]),
    contactPhone: new FormControl('', { nonNullable: true, validators: [Validators.required, Validators.maxLength(20), Validators.pattern(/^\+?[0-9][0-9\s-]{6,18}[0-9]$/)] }),
    contactEmail: new FormControl('', { nonNullable: true, validators: [Validators.email, Validators.maxLength(254)] }),
    is24x7: new FormControl(false, { nonNullable: true }),
  });

  ngOnInit(): void {
    this.lookups.load().pipe(takeUntilDestroyed(this.destroyRef)).subscribe((value) => this.areas.set(value.areas ?? []));
    this.route.paramMap.pipe(takeUntilDestroyed(this.destroyRef)).subscribe((params) => {
      this.facilityId = Number(params.get('id'));
      this.reload();
    });
  }

  protected panelState(): 'loading' | 'empty' | 'error' {
    const current = this.state();
    return current === 'ready' ? 'empty' : current;
  }

  protected reload(): void {
    this.loadSub?.unsubscribe();
    if (!Number.isInteger(this.facilityId) || this.facilityId <= 0) {
      this.error.set('The facility identifier is not valid.');
      this.state.set('error');
      return;
    }
    this.state.set('loading');
    this.error.set('');
    this.saveError.set('');
    this.saveConflict.set(false);
    this.loadSub = this.operations
      .getFacility(this.facilityId)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (facility) => {
          this.facility.set(facility);
          this.form.patchValue({
            name: facility.name ?? '',
            licenseNo: facility.licenseNo ?? '',
            addressLine: facility.addressLine ?? '',
            areaId: facility.areaId,
            city: facility.city ?? '',
            pincode: facility.pincode ?? '',
            latitude: facility.latitude,
            longitude: facility.longitude,
            contactPhone: facility.contactPhone ?? '',
            contactEmail: facility.contactEmail ?? '',
            is24x7: facility.is24x7,
          });
          this.form.markAsPristine();
          this.editing.set(false);
          this.state.set('ready');
        },
        error: (err) => {
          this.facility.set(null);
          this.error.set(errorMessage(err, 'Could not load this facility.'));
          this.state.set('error');
        },
      });
  }

  protected cancelEdit(): void {
    const item = this.facility();
    if (!item) return;
    this.form.patchValue({
      name: item.name ?? '',
      licenseNo: item.licenseNo ?? '',
      addressLine: item.addressLine ?? '',
      areaId: item.areaId,
      city: item.city ?? '',
      pincode: item.pincode ?? '',
      latitude: item.latitude,
      longitude: item.longitude,
      contactPhone: item.contactPhone ?? '',
      contactEmail: item.contactEmail ?? '',
      is24x7: item.is24x7,
    });
    this.editing.set(false);
    this.saveError.set('');
    this.saveConflict.set(false);
  }

  protected save(): void {
    const current = this.facility();
    if (!current || this.saving()) return;
    this.saveError.set('');
    this.saveConflict.set(false);
    if (this.form.invalid) {
      this.form.markAllAsTouched();
      this.saveError.set('Please correct the highlighted fields before saving.');
      return;
    }
    const v = this.form.getRawValue();
    const body: FacilityUpdate = {
      name: v.name.trim(),
      licenseNo: v.licenseNo.trim() || null,
      addressLine: v.addressLine.trim(),
      areaId: v.areaId!,
      city: v.city.trim(),
      pincode: v.pincode.trim(),
      latitude: v.latitude,
      longitude: v.longitude,
      contactPhone: v.contactPhone.trim(),
      contactEmail: v.contactEmail.trim(),
      is24x7: v.is24x7,
      rowVersion: current.rowVersion,
    };
    this.saving.set(true);
    this.operations.updateFacility(current.facilityId, body)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: () => {
          this.saving.set(false);
          this.ui.success('Facility profile updated.');
          this.reload();
        },
        error: (err) => {
          this.saving.set(false);
          this.saveConflict.set(err?.status === 409);
          this.saveError.set(err?.status === 409
            ? 'This facility changed since you opened it. Reload the latest version before trying again.'
            : errorMessage(err, 'The facility could not be updated.'));
        },
      });
  }
}
