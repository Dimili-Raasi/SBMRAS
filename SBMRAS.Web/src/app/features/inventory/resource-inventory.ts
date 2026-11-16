import { ChangeDetectionStrategy, Component, DestroyRef, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { FormControl, FormGroup, ReactiveFormsModule, Validators } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { MatButtonModule } from '@angular/material/button';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatIconModule } from '@angular/material/icon';
import { MatInputModule } from '@angular/material/input';
import { MatSelectModule } from '@angular/material/select';
import { Subscription } from 'rxjs';

import { ViewState } from '../../core/models/api.models';
import { Facility, ResourceInventoryItem, ResourceInventoryUpdate } from '../../core/models/operations.models';
import { Permissions } from '../../core/models/permissions';
import { OperationsService } from '../../core/services/operations.service';
import { UiService } from '../../core/services/ui.service';
import { errorMessage } from '../../core/utils/api-error';
import { HasPermissionDirective } from '../../core/directives/has-permission.directive';
import { FreshnessBadge } from '../../shared/components/freshness-badge';
import { PageHeader } from '../../shared/components/page-header';
import { StatePanel } from '../../shared/components/state-panel';
import { StatusChip } from '../../shared/components/status-chip';

@Component({
  selector: 'sb-resource-inventory',
  standalone: true,
  imports: [
    CommonModule,
    ReactiveFormsModule,
    MatButtonModule,
    MatFormFieldModule,
    MatIconModule,
    MatInputModule,
    MatSelectModule,
    HasPermissionDirective,
    FreshnessBadge,
    PageHeader,
    StatePanel,
    StatusChip,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <main class="page">
      <sb-page-header title="Resource Inventory" subtitle="Report medical resource capacity and operational status." icon="inventory_2" />
      @if (facilityState() !== 'ready') {
        <sb-state-panel [state]="facilityPanelState()"
          [message]="facilityError() || 'No hospital facilities are available to your account.'" (retry)="loadFacilities()" />
      } @else {
        <section class="picker">
          <mat-form-field appearance="outline">
            <mat-label>Facility</mat-label>
            <mat-select [value]="selectedFacilityId()" (selectionChange)="selectFacility($event.value)" aria-label="Select facility">
              @for (facility of facilities(); track facility.facilityId) {
                <mat-option [value]="facility.facilityId">{{ facility.name }} · {{ facility.facilityCode }}</mat-option>
              }
            </mat-select>
          </mat-form-field>
          @if (selectedFacility()) { <span class="facility-type">{{ selectedFacility()?.city || 'Location not reported' }} · Last report {{ selectedFacility()?.lastUpdateAt ? (selectedFacility()?.lastUpdateAt | date:'medium') : 'Not reported' }}</span> }
        </section>

        @if (state() !== 'ready') {
          <sb-state-panel [state]="panelState()" [message]="error() || 'No resource inventory has been reported for this facility.'" (retry)="reload()" />
        } @else {
          <section class="inventory" aria-label="Medical resource inventory">
            @for (item of items(); track item.resourceTypeId) {
              <article class="inventory-row">
                <div class="resource-name">
                  <div class="icon"><mat-icon>medical_services</mat-icon></div>
                  <div><h2>{{ item.resourceTypeName }}</h2><p>{{ item.categoryName }} · <span class="mono">{{ item.resourceTypeCode }}</span></p></div>
                </div>
                <div class="quantities">
                  <span><small>Available / Total</small><strong class="mono">{{ quantity(item.availableQuantity) }} / {{ quantity(item.totalQuantity) }} <em>{{ item.unitCode || '' }}</em></strong></span>
                  <span><small>Status</small><sb-status-chip [status]="item.operationalStatus || 'Unknown'" /></span>
                </div>
                <div class="freshness">
                  <sb-freshness-badge [status]="item.freshnessStatus" [lastUpdatedAt]="item.lastUpdatedAt" [validUntil]="item.validUntil" />
                  <small>Verified: {{ item.verificationStatus || 'Not reported' }} · By {{ item.lastUpdatedByName || 'Not reported' }}</small>
                </div>
                <button *sbHasPermission="P.ResourcesManage" mat-stroked-button color="primary" type="button" (click)="edit(item)">
                  <mat-icon>edit</mat-icon>{{ item.resourceInventoryId ? 'Update' : 'Report' }}
                </button>
              </article>
            }
          </section>
          @if (editing()) {
            <section class="editor" aria-label="Update medical resource inventory">
              <div class="editor-head"><div><h2>{{ editing()?.resourceTypeName }}</h2><p>Changes are recorded with your reason and current row version.</p></div><button mat-icon-button type="button" aria-label="Close editor" (click)="cancelEdit()"><mat-icon>close</mat-icon></button></div>
              @if (saveError()) { <div class="form-error" role="alert"><span>{{ saveError() }}</span>@if (saveConflict()) { <button mat-button type="button" (click)="reload()">Reload latest</button> }</div> }
              <form [formGroup]="form" (ngSubmit)="save()">
                <div class="editor-grid">
                  <mat-form-field appearance="outline"><mat-label>Total quantity</mat-label><input matInput type="number" min="0" step="1" formControlName="totalQuantity" /><mat-error>Enter a non-negative whole number.</mat-error></mat-form-field>
                  <mat-form-field appearance="outline"><mat-label>Available quantity</mat-label><input matInput type="number" min="0" step="1" formControlName="availableQuantity" /><mat-error>Enter a non-negative whole number.</mat-error></mat-form-field>
                  <mat-form-field appearance="outline"><mat-label>Operational status</mat-label><mat-select formControlName="operationalStatus"><mat-option value="Operational">Operational</mat-option><mat-option value="PartiallyOperational">Partially operational</mat-option><mat-option value="Unavailable">Unavailable</mat-option><mat-option value="UnderMaintenance">Under maintenance</mat-option></mat-select></mat-form-field>
                  <mat-form-field appearance="outline"><mat-label>Valid until</mat-label><input matInput type="datetime-local" formControlName="validUntil" /><mat-hint>Leave blank if no expiry applies.</mat-hint></mat-form-field>
                  <mat-form-field appearance="outline" class="wide"><mat-label>Notes</mat-label><textarea matInput rows="2" formControlName="notes"></textarea></mat-form-field>
                  <mat-form-field appearance="outline" class="wide"><mat-label>Reason for update</mat-label><textarea matInput rows="2" formControlName="reason"></textarea><mat-error>A reason is required.</mat-error></mat-form-field>
                </div>
                <div class="actions"><button mat-button type="button" (click)="cancelEdit()">Cancel</button><button mat-flat-button color="primary" type="submit" [disabled]="saving()"><mat-icon>save</mat-icon>{{ saving() ? 'Submitting…' : 'Submit update' }}</button></div>
              </form>
            </section>
          }
        }
      }
    </main>
  `,
  styles: [`
    :host { display:block }.page { max-width:1200px; margin:0 auto; padding:1.5rem }
    .picker { display:flex; align-items:center; gap:1rem; max-width:760px }.picker mat-form-field { flex:1 }.facility-type { color:var(--sb-muted); font-size:.82rem }
    .inventory { display:grid; gap:.65rem }.inventory-row { display:grid; grid-template-columns:minmax(210px,1.3fr) minmax(190px,1fr) minmax(190px,1fr) auto; align-items:center; gap:1rem; padding:.9rem 1rem; background:#fff; border:1px solid var(--sb-border); border-radius:10px; box-shadow:0 2px 8px #0b1f3309 }
    .resource-name { display:flex; align-items:center; gap:.75rem; min-width:0 }.icon { display:grid; place-items:center; width:2.5rem; height:2.5rem; flex:none; border-radius:9px; color:var(--sb-teal); background:#e5f4f1 }.resource-name h2 { margin:0; font-size:.95rem }.resource-name p { margin:.25rem 0 0; color:var(--sb-muted); font-size:.78rem }.mono { font-family:'IBM Plex Mono',monospace }
    .quantities { display:flex; gap:1.25rem }.quantities span { display:grid; gap:.35rem }.quantities small,.freshness small { color:var(--sb-muted); font-size:.73rem }.quantities strong { white-space:nowrap }.quantities em { font-style:normal; color:var(--sb-muted); font-size:.75rem }
    .freshness { display:grid; gap:.35rem }.editor { margin-top:1rem; padding:1rem; background:#fff; border:1px solid var(--sb-border); border-top:3px solid var(--sb-teal); border-radius:10px }.editor-head { display:flex; align-items:flex-start; justify-content:space-between }.editor-head h2 { margin:0; font-size:1.05rem }.editor-head p { margin:.3rem 0 1rem; color:var(--sb-muted) }.editor-grid { display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:0 .8rem }.wide { grid-column:1/-1 }.actions { display:flex; justify-content:flex-end; gap:.5rem }
    .form-error { padding:.65rem .8rem; color:#a50c25; background:#fff0f2; border-radius:8px }.mono { font-family:'IBM Plex Mono',monospace }
    @media(max-width:900px) { .inventory-row { grid-template-columns:minmax(0,1fr) minmax(0,1fr) }.inventory-row > button { justify-self:start } }
    @media(max-width:580px) { .page { padding:1rem }.picker { display:block }.inventory-row { grid-template-columns:1fr }.quantities { justify-content:space-between }.editor-grid { grid-template-columns:1fr }.wide { grid-column:auto } }
  `],
})
export class ResourceInventory implements OnInit {
  private readonly operations = inject(OperationsService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly ui = inject(UiService);
  private readonly destroyRef = inject(DestroyRef);

  protected readonly P = Permissions;
  protected readonly facilities = signal<Facility[]>([]);
  protected readonly selectedFacilityId = signal<number | null>(null);
  protected readonly facilityState = signal<ViewState>('loading');
  protected readonly facilityError = signal('');
  protected readonly state = signal<ViewState>('loading');
  protected readonly error = signal('');
  protected readonly items = signal<ResourceInventoryItem[]>([]);
  protected readonly editing = signal<ResourceInventoryItem | null>(null);
  protected readonly saving = signal(false);
  protected readonly saveError = signal('');
  protected readonly saveConflict = signal(false);
  protected readonly form = new FormGroup({
    totalQuantity: new FormControl<number | null>(null, [Validators.required, Validators.min(0), Validators.max(1000000), Validators.pattern(/^\d+$/)]),
    availableQuantity: new FormControl<number | null>(null, [Validators.required, Validators.min(0), Validators.max(1000000), Validators.pattern(/^\d+$/)]),
    operationalStatus: new FormControl('Operational', { nonNullable: true, validators: Validators.required }),
    validUntil: new FormControl(''),
    notes: new FormControl('', { nonNullable: true, validators: Validators.maxLength(1000) }),
    reason: new FormControl('', { nonNullable: true, validators: [Validators.required, Validators.maxLength(500)] }),
  });
  private facilitySub?: Subscription;
  private inventorySub?: Subscription;

  ngOnInit(): void {
    const requested = Number(this.route.snapshot.queryParamMap.get('facilityId'));
    this.loadFacilities(Number.isInteger(requested) && requested > 0 ? requested : null);
  }

  protected facilityPanelState(): 'loading' | 'empty' | 'error' {
    const current = this.facilityState();
    return current === 'ready' ? 'empty' : current;
  }

  protected panelState(): 'loading' | 'empty' | 'error' {
    const current = this.state();
    return current === 'ready' ? 'empty' : current;
  }

  protected selectedFacility(): Facility | null {
    return this.facilities().find((facility) => facility.facilityId === this.selectedFacilityId()) ?? null;
  }

  protected loadFacilities(preferredId: number | null = this.selectedFacilityId()): void {
    this.facilitySub?.unsubscribe();
    this.facilityState.set('loading');
    this.facilityError.set('');
    this.facilitySub = this.operations.searchFacilities({ facilityType: 'Hospital', page: 1, pageSize: 100 })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (result) => {
          const list = (result.items ?? []).filter((item) => item.facilityType === 'Hospital');
          this.facilities.set(list);
          if (!list.length) {
            this.selectedFacilityId.set(null);
            this.facilityState.set('empty');
            this.state.set('empty');
            return;
          }
          const selected = list.find((item) => item.facilityId === preferredId) ?? list[0];
          this.facilityState.set('ready');
          this.selectFacility(selected.facilityId, false);
        },
        error: (err) => {
          this.facilities.set([]);
          this.facilityError.set(errorMessage(err, 'Could not load facilities for this account.'));
          this.facilityState.set('error');
        },
      });
  }

  protected selectFacility(facilityId: number, updateUrl = true): void {
    const id = Number(facilityId);
    if (!this.facilities().some((facility) => facility.facilityId === id)) return;
    this.selectedFacilityId.set(id);
    if (updateUrl) {
      this.router.navigate([], { relativeTo: this.route, queryParams: { facilityId: id }, queryParamsHandling: 'merge', replaceUrl: true });
    }
    this.reload();
  }

  protected reload(): void {
    const id = this.selectedFacilityId();
    if (!id) return;
    this.inventorySub?.unsubscribe();
    this.state.set('loading');
    this.error.set('');
    this.inventorySub = this.operations.getResourceInventory(id).pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
      next: (items) => {
        this.items.set(items ?? []);
        this.state.set(items?.length ? 'ready' : 'empty');
        this.cancelEdit();
      },
      error: (err) => {
        this.items.set([]);
        this.error.set(errorMessage(err, 'Could not load resource inventory.'));
        this.state.set('error');
      },
    });
  }

  protected quantity(value: number | null): string {
    return value === null || value === undefined ? 'Not reported' : String(value);
  }

  protected edit(item: ResourceInventoryItem): void {
    this.editing.set(item);
    this.saveError.set('');
    this.saveConflict.set(false);
    this.form.reset({
      totalQuantity: item.totalQuantity,
      availableQuantity: item.availableQuantity,
      operationalStatus: item.operationalStatus || 'Operational',
      validUntil: this.toLocalDateTime(item.validUntil),
      notes: item.notes ?? '',
      reason: '',
    });
  }

  protected cancelEdit(): void {
    this.editing.set(null);
    this.saveError.set('');
    this.saveConflict.set(false);
  }

  protected save(): void {
    const row = this.editing();
    const facilityId = this.selectedFacilityId();
    if (!row || !facilityId || this.saving()) return;
    this.saveError.set('');
    this.saveConflict.set(false);
    if (this.form.invalid) {
      this.form.markAllAsTouched();
      this.saveError.set('Please correct the highlighted fields.');
      return;
    }
    const value = this.form.getRawValue();
    if (value.availableQuantity! > value.totalQuantity!) {
      this.saveError.set('Available quantity cannot exceed total quantity.');
      return;
    }
    const body: ResourceInventoryUpdate = {
      resourceTypeId: row.resourceTypeId,
      totalQuantity: Number(value.totalQuantity),
      availableQuantity: Number(value.availableQuantity),
      operationalStatus: value.operationalStatus,
      validUntil: value.validUntil ? new Date(value.validUntil).toISOString() : null,
      notes: value.notes.trim() || null,
      reason: value.reason.trim(),
      rowVersion: row.rowVersion,
    };
    this.saving.set(true);
    this.operations.submitResourceUpdate(facilityId, body).pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
      next: () => {
        this.saving.set(false);
        this.ui.success('Resource update submitted for review.');
        this.reload();
      },
      error: (err) => {
        this.saving.set(false);
        this.saveConflict.set(err?.status === 409);
        this.saveError.set(err?.status === 409
          ? 'This inventory row changed since it was loaded. Refresh and retry with the latest version.'
          : errorMessage(err, 'The resource update could not be submitted.'));
      },
    });
  }

  private toLocalDateTime(value: string | null): string {
    if (!value) return '';
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return '';
    const pad = (part: number) => String(part).padStart(2, '0');
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
  }
}
