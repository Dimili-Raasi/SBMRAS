import { ChangeDetectionStrategy, Component, DestroyRef, OnInit, computed, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { MatButtonModule } from '@angular/material/button';
import { MatButtonToggleModule } from '@angular/material/button-toggle';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatIconModule } from '@angular/material/icon';
import { MatProgressBarModule } from '@angular/material/progress-bar';
import { MatSelectModule } from '@angular/material/select';

import { ViewState } from '../../core/models/api.models';
import {
  ImportBatchDetail,
  ImportFacilityOption,
  InventoryKind,
  kindForFacility,
} from '../../core/models/imports.models';
import { ImportsService } from '../../core/services/imports.service';
import { UiService } from '../../core/services/ui.service';
import { ApiError, errorMessage } from '../../core/utils/api-error';
import { newGuid, saveBlob } from '../../core/utils/http.util';
import { PageHeader } from '../../shared/components/page-header';
import { StatePanel } from '../../shared/components/state-panel';
import { MAX_IMPORT_ROWS, ParsedImportRow, rowValuesLabel, sha256Hex, templateCsv, toImportRows } from './import-csv';
import { ImportRowsTable } from './import-rows-table';

const MAX_FILE_BYTES = 1024 * 1024;

@Component({
  selector: 'sb-import-new',
  imports: [
    FormsModule,
    RouterLink,
    MatButtonModule,
    MatButtonToggleModule,
    MatFormFieldModule,
    MatIconModule,
    MatProgressBarModule,
    MatSelectModule,
    PageHeader,
    StatePanel,
    ImportRowsTable,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './import-new.html',
  styleUrl: './imports.scss',
})
export class ImportNew implements OnInit {
  private readonly imports = inject(ImportsService);
  private readonly ui = inject(UiService);
  private readonly router = inject(Router);
  private readonly destroyRef = inject(DestroyRef);

  protected readonly maxRows = MAX_IMPORT_ROWS;
  protected readonly facilityState = signal<ViewState>('loading');
  protected readonly facilityError = signal('');
  protected readonly facilities = signal<ImportFacilityOption[]>([]);

  protected readonly facilityId = signal<number | null>(null);
  protected readonly kind = signal<InventoryKind>('Blood');
  protected readonly fileName = signal('');
  protected readonly fileText = signal('');
  protected readonly fileErrors = signal<string[]>([]);
  protected readonly parsedRows = signal<ParsedImportRow[]>([]);
  protected readonly dragOver = signal(false);
  protected readonly touched = signal(false);

  protected readonly busy = signal(false);
  protected readonly serverErrors = signal<string[]>([]);
  protected readonly batch = signal<ImportBatchDetail | null>(null);
  private commitKey = '';

  protected readonly selectedFacility = computed(
    () => this.facilities().find((f) => f.facilityId === this.facilityId()) ?? null,
  );
  protected readonly kindMismatch = computed(() => {
    const expected = kindForFacility(this.selectedFacility()?.facilityType);
    return expected !== null && expected !== this.kind();
  });
  protected readonly localIssueRows = computed(() => this.parsedRows().filter((r) => r.localErrors.length));
  protected readonly canValidate = computed(
    () =>
      !this.busy() &&
      !!this.facilityId() &&
      !this.kindMismatch() &&
      this.parsedRows().length > 0 &&
      this.fileErrors().length === 0 &&
      !this.batch(),
  );
  protected readonly committable = computed(() => {
    const b = this.batch();
    return !!b && b.status === 'Validated' && (b.validRows ?? 0) + (b.reviewRows ?? 0) > 0;
  });

  ngOnInit(): void {
    this.loadFacilities();
  }

  protected loadFacilities(): void {
    this.facilityState.set('loading');
    this.imports
      .facilityOptions()
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (list) => {
          this.facilities.set(list);
          if (list.length === 1) {
            this.selectFacility(list[0].facilityId);
          }
          this.facilityState.set(list.length ? 'ready' : 'empty');
        },
        error: (err) => {
          this.facilityError.set(errorMessage(err, 'Your facilities could not be loaded.'));
          this.facilityState.set('error');
        },
      });
  }

  protected selectFacility(id: number | null): void {
    this.facilityId.set(id);
    const kind = kindForFacility(this.facilities().find((f) => f.facilityId === id)?.facilityType);
    if (kind && kind !== this.kind()) {
      this.setKind(kind);
    }
  }

  protected setKind(kind: InventoryKind): void {
    this.kind.set(kind);
    if (this.fileText()) {
      this.parse();
    }
  }

  protected downloadTemplate(): void {
    const kind = this.kind();
    const blob = new Blob([templateCsv(kind)], { type: 'text/csv;charset=utf-8' });
    saveBlob(blob, `sbmras-${kind === 'Blood' ? 'blood-stock' : 'medical-resources'}-template.csv`);
  }

  protected onFileInput(event: Event): void {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    if (file) {
      this.readFile(file);
    }
    input.value = '';
  }

  protected onDrop(event: DragEvent): void {
    event.preventDefault();
    this.dragOver.set(false);
    const file = event.dataTransfer?.files?.[0];
    if (file) {
      this.readFile(file);
    }
  }

  protected onDragOver(event: DragEvent): void {
    event.preventDefault();
    this.dragOver.set(true);
  }

  private readFile(file: File): void {
    this.touched.set(true);
    this.reset(false);
    this.fileName.set(file.name);
    if (!/\.csv$/i.test(file.name)) {
      this.fileErrors.set(['Only .csv files are supported. Download the template to get started.']);
      return;
    }
    if (file.size > MAX_FILE_BYTES) {
      this.fileErrors.set(['The file is larger than 1 MB. Split it into smaller files.']);
      return;
    }
    file
      .text()
      .then((text) => {
        this.fileText.set(text);
        this.parse();
      })
      .catch(() => this.fileErrors.set(['The file could not be read. Check it is a plain-text CSV.']));
  }

  private parse(): void {
    const result = toImportRows(this.fileText(), this.kind());
    this.fileErrors.set(result.fileErrors);
    this.parsedRows.set(result.rows);
  }

  protected rowLabel(row: ParsedImportRow): string {
    return rowValuesLabel(row);
  }

  protected async validate(): Promise<void> {
    this.touched.set(true);
    const facilityId = this.facilityId();
    if (!this.canValidate() || !facilityId) {
      return;
    }
    this.busy.set(true);
    this.serverErrors.set([]);
    const fileHash = await sha256Hex(this.fileText());
    this.imports
      .stage({
        facilityId,
        inventoryKind: this.kind(),
        fileName: this.fileName().slice(0, 255),
        fileHash,
        rows: this.parsedRows().map(({ localErrors: _ignored, ...row }) => row),
      })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (batch) => {
          this.busy.set(false);
          this.commitKey = newGuid();
          this.batch.set(batch);
        },
        error: (err) => {
          this.busy.set(false);
          this.serverErrors.set(this.mapError(err));
        },
      });
  }

  protected async commit(): Promise<void> {
    const batch = this.batch();
    if (!batch || !this.committable()) {
      return;
    }
    const review = batch.reviewRows ?? 0;
    const ok = await this.ui.confirm({
      title: `Commit ${batch.batchNo}?`,
      message:
        `${batch.validRows ?? 0} valid row(s) will be applied` +
        (review ? ` and ${review} row(s) flagged for review will be sent to the verification queue` : '') +
        '. Invalid and duplicate rows are skipped.',
      confirmText: 'Commit import',
    });
    if (!ok) {
      return;
    }
    this.busy.set(true);
    this.serverErrors.set([]);
    this.imports
      .commit(batch.batchId, this.commitKey || (this.commitKey = newGuid()))
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (result) => {
          this.busy.set(false);
          this.ui.success(`Import ${result.batchNo || batch.batchNo} committed.`);
          this.router.navigate(['/imports', result.batchId || batch.batchId]);
        },
        error: (err) => {
          this.busy.set(false);
          this.serverErrors.set(this.mapError(err));
        },
      });
  }

  protected async cancelBatch(): Promise<void> {
    const batch = this.batch();
    if (!batch) {
      return;
    }
    const ok = await this.ui.confirm({
      title: `Cancel ${batch.batchNo}?`,
      message: 'The staged rows will be discarded. You can upload a corrected file afterwards.',
      confirmText: 'Cancel batch',
      danger: true,
    });
    if (!ok) {
      return;
    }
    this.busy.set(true);
    this.imports
      .cancel(batch.batchId)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: () => {
          this.busy.set(false);
          this.ui.success(`Import ${batch.batchNo} cancelled.`);
          this.reset(true);
        },
        error: (err) => {
          this.busy.set(false);
          this.serverErrors.set(this.mapError(err));
        },
      });
  }

  protected reset(clearFile: boolean): void {
    this.batch.set(null);
    this.serverErrors.set([]);
    this.commitKey = '';
    if (clearFile) {
      this.fileName.set('');
      this.fileText.set('');
      this.parsedRows.set([]);
      this.fileErrors.set([]);
    } else {
      this.fileErrors.set([]);
      this.parsedRows.set([]);
    }
  }

  protected count(value: number | null | undefined): string {
    return value === null || value === undefined ? 'Not reported' : String(value);
  }

  private mapError(err: unknown): string[] {
    if (err instanceof ApiError) {
      if (err.status === 409 && /hash|already|duplicate/i.test(err.message)) {
        return [`${err.message} This file appears to have been imported already.`];
      }
      if (err.status === 403) {
        return [err.message || 'You are not assigned to this facility.'];
      }
      return [err.message || 'The request failed.', ...(err.errors ?? [])];
    }
    return [errorMessage(err)];
  }
}
