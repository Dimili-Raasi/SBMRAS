import { ChangeDetectionStrategy, Component, computed, input, signal } from '@angular/core';
import { DatePipe } from '@angular/common';
import { MatButtonToggleModule } from '@angular/material/button-toggle';

import { ImportRow, InventoryKind } from '../../core/models/imports.models';
import { rowValuesLabel, splitMessages } from './import-csv';

/** Row-level validation results for a staged/committed import batch. */
@Component({
  selector: 'sb-import-rows-table',
  imports: [DatePipe, MatButtonToggleModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  styleUrl: './imports.scss',
  template: `
    <div class="row-filter">
      <mat-button-toggle-group
        [value]="filter()"
        (change)="filter.set($event.value)"
        hideSingleSelectionIndicator
        aria-label="Filter rows by validation status"
      >
        <mat-button-toggle value="All">All ({{ rows().length }})</mat-button-toggle>
        @for (s of statuses; track s) {
          @if (countOf(s) > 0) {
            <mat-button-toggle [value]="s">{{ s }} ({{ countOf(s) }})</mat-button-toggle>
          }
        }
      </mat-button-toggle-group>
    </div>
    @if (!filtered().length) {
      <p class="muted">No rows to show.</p>
    } @else {
      <div class="table-responsive">
        <table class="sb-table">
          <thead>
            <tr>
              <th class="num">#</th>
              <th>Item</th>
              @if (kind() === 'Blood') {
                <th class="num">Quantity</th>
                <th>Earliest expiry</th>
              } @else {
                <th class="num">Total</th>
                <th class="num">Available</th>
                <th>Status</th>
              }
              <th>Valid until</th>
              <th>Result</th>
              <th>Errors / warnings</th>
            </tr>
          </thead>
          <tbody>
            @for (r of filtered(); track r.rowNumber) {
              <tr [class]="'row-' + (r.validationStatus || '').toLowerCase()">
                <td class="num mono">{{ r.rowNumber }}</td>
                <td>
                  <div class="mono">{{ label(r) }}</div>
                  <div class="raw" [title]="r.rawData || ''">{{ r.rawData }}</div>
                </td>
                @if (kind() === 'Blood') {
                  <td class="num mono">{{ qty(r.quantity) }}</td>
                  <td>{{ r.earliestExpiryDate ? (r.earliestExpiryDate | date: 'dd MMM yyyy') : '—' }}</td>
                } @else {
                  <td class="num mono">{{ qty(r.totalQuantity) }}</td>
                  <td class="num mono">{{ qty(r.availableQuantity) }}</td>
                  <td>{{ r.operationalStatus || '—' }}</td>
                }
                <td>{{ r.validUntil ? (r.validUntil | date: 'dd MMM, HH:mm') : 'Default TTL' }}</td>
                <td>
                  <span [class]="'row-status row-status--' + (r.validationStatus || '').toLowerCase()">
                    {{ r.validationStatus === 'Review' ? 'Needs review' : r.validationStatus }}
                  </span>
                </td>
                <td>
                  @let msgs = messages(r);
                  @if (msgs.length) {
                    <ul class="messages">
                      @for (m of msgs; track $index) {
                        <li>{{ m }}</li>
                      }
                    </ul>
                  } @else {
                    <span class="muted">—</span>
                  }
                </td>
              </tr>
            }
          </tbody>
        </table>
      </div>
    }
  `,
})
export class ImportRowsTable {
  readonly rows = input.required<ImportRow[]>();
  readonly kind = input<InventoryKind>('Blood');

  protected readonly statuses = ['Valid', 'Review', 'Duplicate', 'Invalid', 'Applied'];
  protected readonly filter = signal<string>('All');
  protected readonly filtered = computed(() =>
    this.filter() === 'All' ? this.rows() : this.rows().filter((r) => r.validationStatus === this.filter()),
  );

  protected countOf(status: string): number {
    return this.rows().filter((r) => r.validationStatus === status).length;
  }

  protected label(r: ImportRow): string {
    return rowValuesLabel(r);
  }

  protected qty(value: number | null | undefined): string {
    return value === null || value === undefined ? 'Not reported' : String(value);
  }

  protected messages(r: ImportRow): string[] {
    const msgs = splitMessages(r.errorMessages);
    if (!msgs.length && r.errorCodes) {
      return splitMessages(r.errorCodes.replace(/,/g, ';'));
    }
    return msgs;
  }
}
