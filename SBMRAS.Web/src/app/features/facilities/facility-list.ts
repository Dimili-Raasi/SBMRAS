import { ChangeDetectionStrategy, Component, DestroyRef, OnInit, inject, signal } from '@angular/core';
import { CommonModule, DatePipe } from '@angular/common';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { FormControl, ReactiveFormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { MatButtonModule } from '@angular/material/button';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatIconModule } from '@angular/material/icon';
import { MatInputModule } from '@angular/material/input';
import { MatPaginatorModule, PageEvent } from '@angular/material/paginator';
import { MatSelectModule } from '@angular/material/select';
import { Subscription, debounceTime, distinctUntilChanged } from 'rxjs';

import { ViewState } from '../../core/models/api.models';
import { Facility } from '../../core/models/operations.models';
import { OperationsService } from '../../core/services/operations.service';
import { errorMessage } from '../../core/utils/api-error';
import { PageHeader } from '../../shared/components/page-header';
import { QualityGauge } from '../../shared/components/quality-gauge';
import { StatePanel } from '../../shared/components/state-panel';
import { StatusChip } from '../../shared/components/status-chip';

@Component({
  selector: 'sb-facility-list',
  standalone: true,
  imports: [
    CommonModule,
    DatePipe,
    ReactiveFormsModule,
    RouterLink,
    MatButtonModule,
    MatFormFieldModule,
    MatIconModule,
    MatInputModule,
    MatPaginatorModule,
    MatSelectModule,
    PageHeader,
    QualityGauge,
    StatePanel,
    StatusChip,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './facility-list.html',
  styleUrl: './facility-list.scss',
})
export class FacilityList implements OnInit {
  private readonly operations = inject(OperationsService);
  private readonly destroyRef = inject(DestroyRef);

  protected readonly state = signal<ViewState>('loading');
  protected readonly error = signal('');
  protected readonly facilities = signal<Facility[]>([]);
  protected readonly total = signal(0);
  protected readonly page = signal(1);
  protected readonly pageSize = signal(20);
  protected readonly search = new FormControl('', { nonNullable: true });
  protected readonly facilityType = new FormControl('', { nonNullable: true });
  private loadSub?: Subscription;

  ngOnInit(): void {
    this.search.valueChanges
      .pipe(debounceTime(300), distinctUntilChanged(), takeUntilDestroyed(this.destroyRef))
      .subscribe(() => {
        this.page.set(1);
        this.reload();
      });
    this.facilityType.valueChanges.pipe(takeUntilDestroyed(this.destroyRef)).subscribe(() => {
      this.page.set(1);
      this.reload();
    });
    this.reload();
  }

  protected panelState(): 'loading' | 'empty' | 'error' {
    const current = this.state();
    return current === 'ready' ? 'empty' : current;
  }

  protected reload(): void {
    this.loadSub?.unsubscribe();
    this.state.set('loading');
    this.error.set('');
    this.loadSub = this.operations
      .searchFacilities({
        search: this.search.value.trim() || null,
        facilityType: this.facilityType.value || null,
        page: this.page(),
        pageSize: this.pageSize(),
      })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (result) => {
          this.facilities.set(result.items ?? []);
          this.total.set(result.totalCount ?? 0);
          this.state.set(result.items?.length ? 'ready' : 'empty');
        },
        error: (err) => {
          this.facilities.set([]);
          this.total.set(0);
          this.error.set(errorMessage(err, 'Could not load your facilities.'));
          this.state.set('error');
        },
      });
  }

  protected onPage(event: PageEvent): void {
    this.page.set(event.pageIndex + 1);
    this.pageSize.set(event.pageSize);
    this.reload();
  }
}
