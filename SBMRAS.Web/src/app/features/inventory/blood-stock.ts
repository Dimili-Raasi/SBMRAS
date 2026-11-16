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
import { BloodStockItem, BloodStockUpdate, Facility } from '../../core/models/operations.models';
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
  selector: 'sb-blood-stock',
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
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <main class="page">
      <sb-page-header title="Blood Stock" subtitle="Maintain a current ABO/Rh and component-level stock report." icon="bloodtype">
        @if (state() === 'ready') {
          <button *sbHasPermission="P.BloodStockManage" mat-stroked-button color="primary" type="button" [disabled]="confirming() || !confirmableIds().length" (click)="confirmCurrent()">
            <mat-icon>verified</mat-icon>{{ confirming() ? 'Confirming…' : 'Confirm current stock' }}
          </button>
        }
      </sb-page-header>
      @if (facilityState() !== 'ready') {
        <sb-state-panel [state]="facilityPanelState()" [message]="facilityError() || 'No blood bank facilities are available to your account.'" (retry)="loadFacilities()" />
      } @else {
        <section class="picker">
          <mat-form-field appearance="outline">
            <mat-label>Blood bank</mat-label>
            <mat-select [value]="selectedFacilityId()" (selectionChange)="selectFacility($event.value)" aria-label="Select blood bank">
              @for (facility of facilities(); track facility.facilityId) {
                <mat-option [value]="facility.facilityId">{{ facility.name }} · {{ facility.facilityCode }}</mat-option>
              }
            </mat-select>
          </mat-form-field>
          @if (selectedFacility()) { <span class="facility-type">{{ selectedFacility()?.city || 'Location not reported' }} · Last report {{ selectedFacility()?.lastUpdateAt ? (selectedFacility()?.lastUpdateAt | date:'medium') : 'Not reported' }}</span> }
        </section>
        @if (state() !== 'ready') {
          <sb-state-panel [state]="panelState()" [message]="error() || 'No blood stock records are available for this facility.'" (retry)="reload()" />
        } @else {
          <section class="stock-list" aria-label="Blood stock matrix">
            @for (item of items(); track item.componentId + '-' + item.aboGroup + '-' + item.rhFactor) {
              <article class="stock-row">
                <div class="group">
                  <span class="blood-tile">{{ item.bloodGroup }}</span>
                  <div><h2>{{ item.componentName }}</h2><p><span class="mono">{{ item.componentCode }}</span> · {{ item.aboGroup }} / {{ item.rhFactor }}</p></div>
                </div>
                <div class="amount"><small>Reported stock</small><strong class="mono">{{ quantity(item.quantity) }} <em>{{ item.unitCode || '' }}</em></strong></div>
                <div class="freshness">
                  <sb-freshness-badge [status]="item.freshnessStatus" [lastUpdatedAt]="item.lastUpdatedAt" [validUntil]="item.validUntil" />
                  <small>Expiry {{ item.earliestExpiryDate ? (item.earliestExpiryDate | date:'mediumDate') : 'Not reported' }}</small>
                  <small>Verification: {{ item.verificationStatus || 'Not reported' }}</small>
                </div>
                <button *sbHasPermission="P.BloodStockManage" mat-stroked-button color="primary" type="button" (click)="edit(item)">
                  <mat-icon>edit</mat-icon>{{ item.inventoryId ? 'Update' : 'Report' }}
                </button>
              </article>
            }
          </section>
          @if (editing()) {
            <section class="editor" aria-label="Update blood stock">
              <div class="editor-head"><div><h2>{{ editing()?.componentName }} · {{ editing()?.bloodGroup }}</h2><p>Updates include a required reason and the current row version.</p></div><button mat-icon-button type="button" aria-label="Close editor" (click)="cancelEdit()"><mat-icon>close</mat-icon></button></div>
              @if (saveError()) { <div class="form-error" role="alert"><span>{{ saveError() }}</span>@if (saveConflict()) { <button mat-button type="button" (click)="reload()">Reload latest</button> }</div> }
              <form [formGroup]="form" (ngSubmit)="save()">
                <div class="editor-grid">
                  <mat-form-field appearance="outline"><mat-label>Quantity</mat-label><input matInput type="number" min="0" step="1" formControlName="quantity" /><mat-error>Enter a non-negative whole number.</mat-error></mat-form-field>
                  <mat-form-field appearance="outline"><mat-label>Earliest expiry date</mat-label><input matInput type="date" formControlName="earliestExpiryDate" /><mat-hint>Leave blank if not applicable.</mat-hint></mat-form-field>
                  <mat-form-field appearance="outline"><mat-label>Report valid until</mat-label><input matInput type="datetime-local" formControlName="validUntil" /><mat-hint>When this report should be considered stale.</mat-hint></mat-form-field>
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
    .stock-list { display:grid; gap:.65rem }.stock-row { display:grid; grid-template-columns:minmax(230px,1.3fr) minmax(140px,.7fr) minmax(200px,1fr) auto; align-items:center; gap:1rem; padding:.9rem 1rem; background:#fff; border:1px solid var(--sb-border); border-radius:10px; box-shadow:0 2px 8px #0b1f3309 }
    .group { display:flex; align-items:center; gap:.75rem; min-width:0 }.blood-tile { display:grid; place-items:center; width:3.1rem; height:2.6rem; flex:none; border:1px solid var(--sb-primary); border-radius:8px; color:var(--sb-primary); font:700 1rem 'IBM Plex Mono',monospace }.group h2 { margin:0; font-size:.95rem }.group p { margin:.25rem 0 0; color:var(--sb-muted); font-size:.78rem }.mono { font-family:'IBM Plex Mono',monospace }
    .amount { display:grid; gap:.35rem }.amount small,.freshness small { color:var(--sb-muted); font-size:.73rem }.amount strong { font-size:1.1rem }.amount em { font-style:normal; color:var(--sb-muted); font-size:.75rem }.freshness { display:grid; gap:.25rem }
    .editor { margin-top:1rem; padding:1rem; background:#fff; border:1px solid var(--sb-border); border-top:3px solid var(--sb-primary); border-radius:10px }.editor-head { display:flex; align-items:flex-start; justify-content:space-between }.editor-head h2 { margin:0; font-size:1.05rem }.editor-head p { margin:.3rem 0 1rem; color:var(--sb-muted) }.editor-grid { display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:0 .8rem }.wide { grid-column:1/-1 }.actions { display:flex; justify-content:flex-end; gap:.5rem }
    .form-error { padding:.65rem .8rem; color:#a50c25; background:#fff0f2; border-radius:8px }
    @media(max-width:900px) { .stock-row { grid-template-columns:minmax(0,1fr) minmax(0,1fr) }.stock-row > button { justify-self:start } }
    @media(max-width:580px) { .page { padding:1rem }.picker { display:block }.stock-row { grid-template-columns:1fr }.editor-grid { grid-template-columns:1fr }.wide { grid-column:auto } }
  `],
})
export class BloodStock implements OnInit {
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
  protected readonly items = signal<BloodStockItem[]>([]);
  protected readonly editing = signal<BloodStockItem | null>(null);
  protected readonly saving = signal(false);
  protected readonly confirming = signal(false);
  protected readonly saveError = signal('');
  protected readonly saveConflict = signal(false);
  protected readonly form = new FormGroup({
    quantity: new FormControl<number | null>(null, [Validators.required, Validators.min(0), Validators.max(1000000), Validators.pattern(/^\d+$/)]),
    earliestExpiryDate: new FormControl(''),
    validUntil: new FormControl(''),
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
    this.facilitySub = this.operations.searchFacilities({ facilityType: 'BloodBank', page: 1, pageSize: 100 })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (result) => {
          const list = (result.items ?? []).filter((item) => item.facilityType === 'BloodBank');
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
          this.facilityError.set(errorMessage(err, 'Could not load blood banks for this account.'));
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
    this.inventorySub = this.operations.getBloodStock(id).pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
      next: (items) => {
        this.items.set(items ?? []);
        this.state.set(items?.length ? 'ready' : 'empty');
        this.cancelEdit();
      },
      error: (err) => {
        this.items.set([]);
        this.error.set(errorMessage(err, 'Could not load blood stock.'));
        this.state.set('error');
      },
    });
  }

  protected quantity(value: number | null): string {
    return value === null || value === undefined ? 'Not reported' : String(value);
  }

  protected confirmableIds(): number[] {
    return this.items().flatMap((item) => item.inventoryId === null ? [] : [item.inventoryId]);
  }

  protected async confirmCurrent(): Promise<void> {
    const facilityId = this.selectedFacilityId();
    const ids = this.confirmableIds();
    if (!facilityId || !ids.length || this.confirming()) return;
    const accepted = await this.ui.confirm({
      title: 'Confirm reported blood stock',
      message: `Reconfirm ${ids.length} existing stock row(s) as unchanged and refresh their reporting validity?`,
      confirmText: 'Confirm current stock',
    });
    if (!accepted) return;
    this.confirming.set(true);
    this.operations.confirmBloodStock(facilityId, ids).pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
      next: () => {
        this.confirming.set(false);
        this.ui.success('Current blood stock confirmed.');
        this.reload();
      },
      error: (err) => {
        this.confirming.set(false);
        this.ui.error(err?.status === 409
          ? 'Blood stock changed before confirmation. Refresh the list and retry.'
          : errorMessage(err, 'Could not confirm blood stock.'));
      },
    });
  }

  protected edit(item: BloodStockItem): void {
    this.editing.set(item);
    this.saveError.set('');
    this.saveConflict.set(false);
    this.form.reset({
      quantity: item.quantity,
      earliestExpiryDate: this.toDateInput(item.earliestExpiryDate),
      validUntil: this.toLocalDateTime(item.validUntil),
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
    if (value.earliestExpiryDate && new Date(value.earliestExpiryDate).getTime() < new Date().setHours(0, 0, 0, 0)) {
      this.saveError.set('The earliest expiry date cannot be in the past.');
      return;
    }
    const body: BloodStockUpdate = {
      componentId: row.componentId,
      aboGroup: row.aboGroup,
      rhFactor: row.rhFactor,
      quantity: Number(value.quantity),
      earliestExpiryDate: value.earliestExpiryDate ? new Date(`${value.earliestExpiryDate}T00:00:00`).toISOString() : null,
      validUntil: value.validUntil ? new Date(value.validUntil).toISOString() : null,
      reason: value.reason.trim(),
      rowVersion: row.rowVersion,
    };
    this.saving.set(true);
    this.operations.submitBloodStockUpdate(facilityId, body).pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
      next: () => {
        this.saving.set(false);
        this.ui.success('Blood stock update submitted for review.');
        this.reload();
      },
      error: (err) => {
        this.saving.set(false);
        this.saveConflict.set(err?.status === 409);
        this.saveError.set(err?.status === 409
          ? 'This stock row changed since it was loaded. Refresh and retry with the latest version.'
          : errorMessage(err, 'The blood stock update could not be submitted.'));
      },
    });
  }

  private toDateInput(value: string | null): string {
    if (!value) return '';
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? '' : date.toISOString().slice(0, 10);
  }

  private toLocalDateTime(value: string | null): string {
    if (!value) return '';
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return '';
    const pad = (part: number) => String(part).padStart(2, '0');
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
  }
}
