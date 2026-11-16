import { ChangeDetectionStrategy, Component, DestroyRef, OnInit, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import {
  AbstractControl,
  FormControl,
  FormGroup,
  ReactiveFormsModule,
  ValidationErrors,
  Validators,
} from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { MatButtonModule } from '@angular/material/button';
import { MatButtonToggleModule } from '@angular/material/button-toggle';
import { MatCheckboxModule } from '@angular/material/checkbox';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatIconModule } from '@angular/material/icon';
import { MatInputModule } from '@angular/material/input';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';
import { MatSelectModule } from '@angular/material/select';

import { ViewState } from '../../../core/models/api.models';
import { Lookups } from '../../../core/models/lookup.models';
import { REQUEST_URGENCIES, RequestSave, RequestUrgency } from '../../../core/models/requests.models';
import { LookupService } from '../../../core/services/lookup.service';
import { RequestsService } from '../../../core/services/requests.service';
import { SessionService } from '../../../core/services/session.service';
import { UiService } from '../../../core/services/ui.service';
import { ApiError } from '../../../core/utils/api-error';
import { newGuid } from '../../../core/utils/http.util';
import { PageHeader } from '../../../shared/components/page-header';
import { StatePanel } from '../../../shared/components/state-panel';
import { BloodGroupTile } from '../../../shared/components/blood-group-tile';
import { UrgencyBadge } from '../../../shared/components/urgency-badge';
import { requestErrorText } from '../requests-shared';

const MAX_QUANTITY = 50;
const PHONE_PATTERN = /^\+?[0-9][0-9\s-]{6,18}[0-9]$/;

interface BloodGroupOption {
  aboGroup: string;
  rhFactor: string;
}

function futureDateValidator(control: AbstractControl<string | null>): ValidationErrors | null {
  if (!control.value) {
    return null;
  }
  const time = new Date(control.value).getTime();
  if (Number.isNaN(time)) {
    return { invalidDate: true };
  }
  return time <= Date.now() ? { notFuture: true } : null;
}

function toLocalInputValue(date: Date): string {
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

function normalizeRh(value: string | null): string | null {
  if (!value) {
    return null;
  }
  const v = value.trim().toLowerCase();
  if (v === '+' || v === 'pos' || v === 'positive') {
    return 'Positive';
  }
  if (v === '-' || v === 'neg' || v === 'negative') {
    return 'Negative';
  }
  return null;
}

function positiveInt(value: string | null): number | null {
  const n = Number(value);
  return value && Number.isInteger(n) && n > 0 ? n : null;
}

/** /requests/new — create a blood request (contract §4.5, §6 RequestSave; SDD S-04). */
@Component({
  selector: 'sb-request-form',
  imports: [
    ReactiveFormsModule,
    RouterLink,
    MatButtonModule,
    MatButtonToggleModule,
    MatCheckboxModule,
    MatFormFieldModule,
    MatIconModule,
    MatInputModule,
    MatProgressSpinnerModule,
    MatSelectModule,
    PageHeader,
    StatePanel,
    BloodGroupTile,
    UrgencyBadge,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './request-form.html',
  styleUrl: './request-form.scss',
})
export class RequestForm implements OnInit {
  private readonly requests = inject(RequestsService);
  private readonly lookupService = inject(LookupService);
  private readonly session = inject(SessionService);
  private readonly ui = inject(UiService);
  private readonly router = inject(Router);
  private readonly route = inject(ActivatedRoute);
  private readonly destroyRef = inject(DestroyRef);

  protected readonly maxQuantity = MAX_QUANTITY;
  protected readonly urgencies = REQUEST_URGENCIES;
  protected readonly bloodGroups: BloodGroupOption[] = ['A', 'B', 'AB', 'O'].flatMap((abo) => [
    { aboGroup: abo, rhFactor: 'Positive' },
    { aboGroup: abo, rhFactor: 'Negative' },
  ]);

  protected readonly state = signal<ViewState>('loading');
  protected readonly loadError = signal('');
  protected readonly lookups = signal<Lookups | null>(null);
  protected readonly saving = signal(false);
  protected readonly serverError = signal('');
  protected readonly serverErrors = signal<string[]>([]);
  protected readonly preferredFacilityName = signal<string | null>(null);
  protected readonly minNeededBy = toLocalInputValue(new Date());

  /** One key per form instance so double-submits/retries return the same request (contract §3.6). */
  private idempotencyKey = newGuid();

  protected readonly form = new FormGroup({
    aboGroup: new FormControl<string | null>(null, Validators.required),
    rhFactor: new FormControl<string | null>(null, Validators.required),
    componentId: new FormControl<number | null>(null, Validators.required),
    quantityRequested: new FormControl<number | null>(null, [
      Validators.required,
      Validators.min(0.01),
      Validators.max(MAX_QUANTITY),
    ]),
    unitId: new FormControl<number | null>(null, Validators.required),
    urgency: new FormControl<RequestUrgency>('Routine', { nonNullable: true, validators: Validators.required }),
    neededBy: new FormControl<string | null>(null, [Validators.required, futureDateValidator]),
    areaId: new FormControl<number | null>(null, Validators.required),
    hospitalName: new FormControl('', {
      nonNullable: true,
      validators: [Validators.required, Validators.maxLength(200)],
    }),
    preferredFacilityId: new FormControl<number | null>(null),
    patientReference: new FormControl('', { nonNullable: true, validators: Validators.maxLength(50) }),
    contactName: new FormControl('', {
      nonNullable: true,
      validators: [Validators.required, Validators.maxLength(150)],
    }),
    contactPhone: new FormControl('', {
      nonNullable: true,
      validators: [Validators.required, Validators.maxLength(20), Validators.pattern(PHONE_PATTERN)],
    }),
    contactConsent: new FormControl(false, { nonNullable: true, validators: Validators.requiredTrue }),
    notes: new FormControl('', { nonNullable: true, validators: Validators.maxLength(1000) }),
  });

  ngOnInit(): void {
    const user = this.session.user();
    this.form.patchValue({
      contactName: user?.displayName ?? '',
      contactPhone: user?.phone ?? '',
      areaId: user?.areaId ?? null,
    });
    this.loadLookups();
  }

  protected loadLookups(): void {
    this.state.set('loading');
    this.loadError.set('');
    this.lookupService
      .load()
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (lookups) => {
          this.lookups.set(lookups);
          this.applyDefaults(lookups);
          this.applyPrefill(lookups);
          this.state.set('ready');
        },
        error: (err) => {
          this.loadError.set(requestErrorText(err));
          this.state.set('error');
        },
      });
  }

  protected isSelected(option: BloodGroupOption): boolean {
    const v = this.form.getRawValue();
    return v.aboGroup === option.aboGroup && v.rhFactor === option.rhFactor;
  }

  protected pickGroup(option: BloodGroupOption): void {
    this.form.patchValue({ aboGroup: option.aboGroup, rhFactor: option.rhFactor });
    this.form.controls.aboGroup.markAsTouched();
    this.form.controls.rhFactor.markAsTouched();
  }

  protected clearPreferredFacility(): void {
    this.form.controls.preferredFacilityId.setValue(null);
    this.preferredFacilityName.set(null);
  }

  protected bloodGroupInvalid(): boolean {
    const c = this.form.controls;
    return (c.aboGroup.invalid || c.rhFactor.invalid) && (c.aboGroup.touched || c.rhFactor.touched);
  }

  protected submit(): void {
    if (this.saving()) {
      return;
    }
    this.serverError.set('');
    this.serverErrors.set([]);
    if (this.form.invalid) {
      this.form.markAllAsTouched();
      this.serverError.set('Please correct the highlighted fields.');
      return;
    }
    const v = this.form.getRawValue();
    const body: RequestSave = {
      patientReference: v.patientReference.trim() || null,
      aboGroup: v.aboGroup!,
      rhFactor: v.rhFactor!,
      componentId: v.componentId!,
      quantityRequested: Number(v.quantityRequested),
      unitId: v.unitId!,
      urgency: v.urgency,
      neededBy: new Date(v.neededBy!).toISOString(),
      areaId: v.areaId!,
      hospitalName: v.hospitalName.trim(),
      preferredFacilityId: v.preferredFacilityId,
      contactName: v.contactName.trim(),
      contactPhone: v.contactPhone.trim(),
      contactConsent: v.contactConsent,
      notes: v.notes.trim() || null,
    };
    this.saving.set(true);
    this.requests
      .create(body, this.idempotencyKey)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (created) => {
          this.saving.set(false);
          this.idempotencyKey = newGuid();
          this.ui.success(`Request ${created.requestNo} submitted. You will be notified as it progresses.`);
          this.router.navigate(['/requests', created.requestId]);
        },
        error: (err) => {
          this.saving.set(false);
          if (err instanceof ApiError && err.status === 400 && err.errors?.length) {
            this.serverError.set(err.message || 'The request could not be submitted.');
            this.serverErrors.set(err.errors);
          } else {
            this.serverError.set(requestErrorText(err));
          }
        },
      });
  }

  private applyDefaults(lookups: Lookups): void {
    const units = lookups.units ?? [];
    const defaultUnit = units.find((u) => u.code === 'UNITS') ?? units[0];
    if (defaultUnit && !this.form.controls.unitId.value) {
      this.form.controls.unitId.setValue(defaultUnit.unitId);
    }
    if (!this.form.controls.neededBy.value) {
      this.form.controls.neededBy.setValue(toLocalInputValue(new Date(Date.now() + 24 * 3_600_000)));
    }
    const areaId = this.form.controls.areaId.value;
    if (areaId && !(lookups.areas ?? []).some((a) => a.areaId === areaId)) {
      this.form.controls.areaId.setValue(null);
    }
  }

  /** Prefill from search ("Request this blood") query params. */
  private applyPrefill(lookups: Lookups): void {
    const qp = this.route.snapshot.queryParamMap;
    const abo = qp.get('aboGroup')?.toUpperCase() ?? null;
    const rh = normalizeRh(qp.get('rhFactor'));
    if (abo && ['A', 'B', 'AB', 'O'].includes(abo)) {
      this.form.controls.aboGroup.setValue(abo);
    }
    if (rh) {
      this.form.controls.rhFactor.setValue(rh);
    }
    const componentId = positiveInt(qp.get('componentId'));
    if (componentId && (lookups.components ?? []).some((c) => c.componentId === componentId)) {
      this.form.controls.componentId.setValue(componentId);
    }
    const areaId = positiveInt(qp.get('areaId'));
    if (areaId && (lookups.areas ?? []).some((a) => a.areaId === areaId)) {
      this.form.controls.areaId.setValue(areaId);
    }
    const unitId = positiveInt(qp.get('unitId'));
    if (unitId && (lookups.units ?? []).some((u) => u.unitId === unitId)) {
      this.form.controls.unitId.setValue(unitId);
    }
    const qty = Number(qp.get('quantity') ?? qp.get('quantityRequested'));
    if (qty > 0 && qty <= MAX_QUANTITY) {
      this.form.controls.quantityRequested.setValue(qty);
    }
    const urgency = qp.get('urgency') as RequestUrgency | null;
    if (urgency && REQUEST_URGENCIES.includes(urgency)) {
      this.form.controls.urgency.setValue(urgency);
    }
    const facilityId = positiveInt(qp.get('preferredFacilityId') ?? qp.get('facilityId'));
    if (facilityId) {
      this.form.controls.preferredFacilityId.setValue(facilityId);
      this.preferredFacilityName.set(qp.get('facilityName') || `Facility #${facilityId}`);
    }
    const hospital = qp.get('hospitalName');
    if (hospital) {
      this.form.controls.hospitalName.setValue(hospital.slice(0, 200));
    }
  }
}
