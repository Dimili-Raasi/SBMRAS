import { ChangeDetectionStrategy, Component, DestroyRef, OnInit, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { DatePipe } from '@angular/common';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';

import { ViewState } from '../../core/models/api.models';
import { ImportBatchDetail } from '../../core/models/imports.models';
import { ImportsService } from '../../core/services/imports.service';
import { UiService } from '../../core/services/ui.service';
import { ApiError, errorMessage } from '../../core/utils/api-error';
import { newGuid } from '../../core/utils/http.util';
import { PageHeader } from '../../shared/components/page-header';
import { StatePanel } from '../../shared/components/state-panel';
import { ImportRowsTable } from './import-rows-table';

@Component({
  selector: 'sb-import-detail',
  imports: [DatePipe, RouterLink, MatButtonModule, MatIconModule, PageHeader, StatePanel, ImportRowsTable],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './import-detail.html',
  styleUrl: './imports.scss',
})
export class ImportDetail implements OnInit {
  private readonly imports = inject(ImportsService);
  private readonly ui = inject(UiService);
  private readonly route = inject(ActivatedRoute);
  private readonly destroyRef = inject(DestroyRef);

  protected readonly state = signal<ViewState>('loading');
  protected readonly error = signal('');
  protected readonly batch = signal<ImportBatchDetail | null>(null);
  protected readonly busy = signal(false);
  private batchId = 0;
  private commitKey = newGuid();

  ngOnInit(): void {
    this.route.paramMap.pipe(takeUntilDestroyed(this.destroyRef)).subscribe((params) => {
      this.batchId = Number(params.get('id'));
      this.load();
    });
  }

  protected load(): void {
    if (!Number.isInteger(this.batchId) || this.batchId <= 0) {
      this.error.set('Invalid import batch id.');
      this.state.set('error');
      return;
    }
    this.state.set('loading');
    this.imports
      .getById(this.batchId)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (batch) => {
          this.batch.set(batch);
          this.state.set('ready');
        },
        error: (err) => {
          this.error.set(
            err instanceof ApiError && err.status === 404
              ? 'This import batch does not exist or you do not have access to it.'
              : errorMessage(err, 'The import batch could not be loaded.'),
          );
          this.state.set('error');
        },
      });
  }

  protected canCommit(b: ImportBatchDetail): boolean {
    return b.status === 'Validated' && (b.validRows ?? 0) + (b.reviewRows ?? 0) > 0;
  }

  protected async commit(): Promise<void> {
    const b = this.batch();
    if (!b) return;
    const ok = await this.ui.confirm({
      title: `Commit ${b.batchNo}?`,
      message: `${b.validRows ?? 0} valid row(s) will be applied; ${b.reviewRows ?? 0} row(s) go to verification.`,
      confirmText: 'Commit import',
    });
    if (!ok) return;
    this.busy.set(true);
    this.imports
      .commit(b.batchId, this.commitKey)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: () => {
          this.busy.set(false);
          this.ui.success(`Import ${b.batchNo} committed.`);
          this.load();
        },
        error: (err) => {
          this.busy.set(false);
          this.ui.error(errorMessage(err, 'The import could not be committed.'));
          if (err instanceof ApiError && err.status === 409) this.load();
        },
      });
  }

  protected async cancel(): Promise<void> {
    const b = this.batch();
    if (!b) return;
    const ok = await this.ui.confirm({
      title: `Cancel ${b.batchNo}?`,
      message: 'The staged rows will be discarded and nothing will be applied.',
      confirmText: 'Cancel batch',
      danger: true,
    });
    if (!ok) return;
    this.busy.set(true);
    this.imports
      .cancel(b.batchId)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: () => {
          this.busy.set(false);
          this.ui.success(`Import ${b.batchNo} cancelled.`);
          this.load();
        },
        error: (err) => {
          this.busy.set(false);
          this.ui.error(errorMessage(err, 'The import could not be cancelled.'));
        },
      });
  }

  protected count(value: number | null | undefined): string {
    return value === null || value === undefined ? 'Not reported' : String(value);
  }
}
