import { ChangeDetectionStrategy, Component, DestroyRef, OnInit, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { DatePipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { MatButtonModule } from '@angular/material/button';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatIconModule } from '@angular/material/icon';
import { MatPaginatorModule, PageEvent } from '@angular/material/paginator';
import { MatSelectModule } from '@angular/material/select';
import { MatTooltipModule } from '@angular/material/tooltip';

import { ViewState } from '../../core/models/api.models';
import { ImportBatch, ImportFacilityOption } from '../../core/models/imports.models';
import { ImportsService } from '../../core/services/imports.service';
import { errorMessage } from '../../core/utils/api-error';
import { PageHeader } from '../../shared/components/page-header';
import { StatePanel } from '../../shared/components/state-panel';

@Component({
  selector: 'sb-import-list',
  imports: [
    DatePipe,
    FormsModule,
    RouterLink,
    MatButtonModule,
    MatFormFieldModule,
    MatIconModule,
    MatPaginatorModule,
    MatSelectModule,
    MatTooltipModule,
    PageHeader,
    StatePanel,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './import-list.html',
  styleUrl: './imports.scss',
})
export class ImportList implements OnInit {
  private readonly imports = inject(ImportsService);
  private readonly destroyRef = inject(DestroyRef);

  protected readonly state = signal<ViewState>('loading');
  protected readonly error = signal('');
  protected readonly batches = signal<ImportBatch[]>([]);
  protected readonly total = signal(0);
  protected readonly facilities = signal<ImportFacilityOption[]>([]);

  protected facilityId: number | null = null;
  protected status: string | null = null;
  protected page = 1;
  protected pageSize = 20;
  protected readonly statuses = ['Validated', 'Committed', 'Cancelled'];

  ngOnInit(): void {
    this.imports
      .facilityOptions()
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({ next: (f) => this.facilities.set(f), error: () => this.facilities.set([]) });
    this.load();
  }

  protected load(): void {
    this.state.set('loading');
    this.imports
      .search({ facilityId: this.facilityId, status: this.status, page: this.page, pageSize: this.pageSize })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (result) => {
          this.batches.set(result.items);
          this.total.set(result.totalCount ?? result.items.length);
          this.state.set(result.items.length ? 'ready' : 'empty');
        },
        error: (err) => {
          this.error.set(errorMessage(err, 'Import batches could not be loaded.'));
          this.state.set('error');
        },
      });
  }

  protected applyFilters(): void {
    this.page = 1;
    this.load();
  }

  protected onPage(event: PageEvent): void {
    this.page = event.pageIndex + 1;
    this.pageSize = event.pageSize;
    this.load();
  }

  protected count(value: number | null | undefined): string {
    return value === null || value === undefined ? 'Not reported' : String(value);
  }

  protected statusClass(status: string): string {
    return `imp-status imp-status--${(status || 'unknown').toLowerCase()}`;
  }
}
