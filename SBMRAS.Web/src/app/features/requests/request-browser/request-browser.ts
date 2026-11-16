import { ChangeDetectionStrategy, Component, DestroyRef, OnInit, computed, inject, input, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { FormControl, FormGroup, ReactiveFormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { MatButtonModule } from '@angular/material/button';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatIconModule } from '@angular/material/icon';
import { MatInputModule } from '@angular/material/input';
import { MatPaginatorModule, PageEvent } from '@angular/material/paginator';
import { MatSelectModule } from '@angular/material/select';
import { MatTooltipModule } from '@angular/material/tooltip';
import { Subscription, debounceTime, distinctUntilChanged, merge } from 'rxjs';

import { ViewState } from '../../../core/models/api.models';
import { AreaLookup } from '../../../core/models/lookup.models';
import { Permissions } from '../../../core/models/permissions';
import {
  BloodRequest,
  REQUEST_STATUSES,
  REQUEST_URGENCIES,
  RequestSearchQuery,
} from '../../../core/models/requests.models';
import { LookupService } from '../../../core/services/lookup.service';
import { RequestsService } from '../../../core/services/requests.service';
import { HasPermissionDirective } from '../../../core/directives/has-permission.directive';
import { PageHeader } from '../../../shared/components/page-header';
import { StatePanel } from '../../../shared/components/state-panel';
import { StatusChip } from '../../../shared/components/status-chip';
import { UrgencyBadge } from '../../../shared/components/urgency-badge';
import { BloodGroupTile } from '../../../shared/components/blood-group-tile';
import { SbDatePipe } from '../../../shared/pipes/sb-date.pipe';
import { SbRelativePipe } from '../../../shared/pipes/sb-relative.pipe';
import { SbQtyPipe } from '../../../shared/pipes/sb-qty.pipe';
import { requestErrorText, slaLevel, slaText, statusLabel } from '../requests-shared';

export type RequestBrowserMode = 'mine' | 'coordination';

/** Paged, filterable request list used by /requests (own) and /coordination (staff queue). */
@Component({
  selector: 'sb-request-browser',
  imports: [
    ReactiveFormsModule,
    RouterLink,
    MatButtonModule,
    MatFormFieldModule,
    MatIconModule,
    MatInputModule,
    MatPaginatorModule,
    MatSelectModule,
    MatTooltipModule,
    HasPermissionDirective,
    PageHeader,
    StatePanel,
    StatusChip,
    UrgencyBadge,
    BloodGroupTile,
    SbDatePipe,
    SbRelativePipe,
    SbQtyPipe,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './request-browser.html',
  styleUrl: './request-browser.scss',
})
export class RequestBrowser implements OnInit {
  readonly mode = input<RequestBrowserMode>('mine');

  private readonly requests = inject(RequestsService);
  private readonly lookups = inject(LookupService);
  private readonly router = inject(Router);
  private readonly route = inject(ActivatedRoute);
  private readonly destroyRef = inject(DestroyRef);

  protected readonly P = Permissions;
  protected readonly statuses = REQUEST_STATUSES;
  protected readonly urgencies = REQUEST_URGENCIES;
  protected readonly aboGroups = ['A', 'B', 'AB', 'O'];
  protected readonly statusLabel = statusLabel;
  protected readonly slaLevel = slaLevel;
  protected readonly slaText = slaText;

  protected readonly state = signal<ViewState>('loading');
  protected readonly error = signal('');
  protected readonly items = signal<BloodRequest[]>([]);
  protected readonly total = signal(0);
  protected readonly page = signal(1);
  protected readonly pageSize = signal(20);
  protected readonly areas = signal<AreaLookup[]>([]);
  protected readonly now = signal(Date.now());
  private readonly filterTick = signal(0);

  protected readonly isCoordination = computed(() => this.mode() === 'coordination');
  protected readonly detailBase = computed(() => (this.isCoordination() ? '/coordination' : '/requests'));

  protected readonly filters = new FormGroup({
    search: new FormControl('', { nonNullable: true }),
    status: new FormControl('', { nonNullable: true }),
    urgency: new FormControl('', { nonNullable: true }),
    aboGroup: new FormControl('', { nonNullable: true }),
    areaId: new FormControl<number | null>(null),
  });

  protected readonly hasFilters = computed(() => {
    this.filterTick();
    const v = this.filters.getRawValue();
    return !!(v.search || v.status || v.urgency || v.aboGroup || v.areaId);
  });

  private loadSub?: Subscription;

  ngOnInit(): void {
    const qp = this.route.snapshot.queryParamMap;
    this.filters.patchValue(
      {
        search: qp.get('search') ?? '',
        status: qp.get('status') ?? '',
        urgency: qp.get('urgency') ?? '',
        aboGroup: qp.get('aboGroup') ?? '',
        areaId: qp.get('areaId') ? Number(qp.get('areaId')) : null,
      },
      { emitEvent: false },
    );
    const page = Number(qp.get('page'));
    if (page > 0) {
      this.page.set(page);
    }
    this.filterTick.update((n) => n + 1);

    this.lookups
      .load()
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({ next: (l) => this.areas.set(l.areas ?? []), error: () => this.areas.set([]) });

    this.filters.controls.search.valueChanges
      .pipe(debounceTime(350), distinctUntilChanged(), takeUntilDestroyed(this.destroyRef))
      .subscribe(() => this.applyFilters());
    merge(
      this.filters.controls.status.valueChanges,
      this.filters.controls.urgency.valueChanges,
      this.filters.controls.aboGroup.valueChanges,
      this.filters.controls.areaId.valueChanges,
    )
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe(() => this.applyFilters());

    this.reload();
  }

  protected quickStatus(status: string): void {
    this.filters.controls.status.setValue(this.filters.controls.status.value === status ? '' : status);
  }

  protected clearFilters(): void {
    this.filters.reset({ search: '', status: '', urgency: '', aboGroup: '', areaId: null }, { emitEvent: false });
    this.applyFilters();
  }

  protected onPage(event: PageEvent): void {
    this.page.set(event.pageIndex + 1);
    this.pageSize.set(event.pageSize);
    this.reload();
  }

  protected open(row: BloodRequest): void {
    this.router.navigate([this.detailBase(), row.requestId]);
  }

  reload(): void {
    this.loadSub?.unsubscribe();
    this.state.set('loading');
    this.error.set('');
    this.now.set(Date.now());
    const v = this.filters.getRawValue();
    const query: RequestSearchQuery = {
      scope: this.isCoordination() ? 'all' : 'mine',
      search: v.search.trim() || null,
      status: v.status || null,
      urgency: v.urgency || null,
      aboGroup: v.aboGroup || null,
      areaId: v.areaId,
      page: this.page(),
      pageSize: this.pageSize(),
    };
    this.syncUrl(query);
    this.loadSub = this.requests
      .search(query)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (result) => {
          this.items.set(result.items);
          this.total.set(result.totalCount);
          this.state.set(result.items.length ? 'ready' : 'empty');
        },
        error: (err) => {
          this.items.set([]);
          this.error.set(requestErrorText(err));
          this.state.set('error');
        },
      });
  }

  private applyFilters(): void {
    this.filterTick.update((n) => n + 1);
    this.page.set(1);
    this.reload();
  }

  private syncUrl(query: RequestSearchQuery): void {
    this.router.navigate([], {
      relativeTo: this.route,
      replaceUrl: true,
      queryParams: {
        search: query.search || null,
        status: query.status || null,
        urgency: query.urgency || null,
        aboGroup: query.aboGroup || null,
        areaId: query.areaId ?? null,
        page: query.page && query.page > 1 ? query.page : null,
      },
    });
  }
}
