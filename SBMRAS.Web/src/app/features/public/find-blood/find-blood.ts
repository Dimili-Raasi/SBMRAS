import { ChangeDetectionStrategy, Component, DestroyRef, OnInit, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { FormControl, FormGroup, ReactiveFormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { MatButtonModule } from '@angular/material/button';
import { MatCheckboxModule } from '@angular/material/checkbox';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatIconModule } from '@angular/material/icon';
import { MatInputModule } from '@angular/material/input';
import { MatPaginatorModule, PageEvent } from '@angular/material/paginator';
import { MatSelectModule } from '@angular/material/select';
import { Subscription, debounceTime, distinctUntilChanged, merge } from 'rxjs';

import { ViewState } from '../../../core/models/api.models';
import { AreaLookup, ComponentLookup } from '../../../core/models/lookup.models';
import { BloodAvailability, BloodSearchQuery } from '../../../core/models/public.models';
import { LookupService } from '../../../core/services/lookup.service';
import { PublicService, publicErrorText } from '../../../core/services/public.service';
import { SessionService } from '../../../core/services/session.service';
import { BloodGroupTile } from '../../../shared/components/blood-group-tile';
import { FreshnessBadge } from '../../../shared/components/freshness-badge';
import { PageHeader } from '../../../shared/components/page-header';
import { QualityGauge } from '../../../shared/components/quality-gauge';
import { StatePanel } from '../../../shared/components/state-panel';
import { SbQtyPipe } from '../../../shared/pipes/sb-qty.pipe';

@Component({
  selector: 'sb-find-blood',
  standalone: true,
  imports: [
    ReactiveFormsModule,
    MatButtonModule,
    MatCheckboxModule,
    MatFormFieldModule,
    MatIconModule,
    MatInputModule,
    MatPaginatorModule,
    MatSelectModule,
    BloodGroupTile,
    FreshnessBadge,
    PageHeader,
    QualityGauge,
    StatePanel,
    SbQtyPipe,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './find-blood.html',
  styleUrl: './find-blood.scss',
})
export class FindBlood implements OnInit {
  private readonly publicApi = inject(PublicService);
  private readonly lookupService = inject(LookupService);
  private readonly session = inject(SessionService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly destroyRef = inject(DestroyRef);

  protected readonly items = signal<BloodAvailability[]>([]);
  protected readonly areas = signal<AreaLookup[]>([]);
  protected readonly components = signal<ComponentLookup[]>([]);
  protected readonly state = signal<ViewState>('loading');
  protected readonly error = signal('');
  protected readonly total = signal(0);
  protected readonly page = signal(1);
  protected readonly pageSize = signal(12);
  protected readonly isAuthenticated = this.session.isAuthenticated;
  private loadSub?: Subscription;

  protected readonly filters = new FormGroup({
    search: new FormControl('', { nonNullable: true }),
    aboGroup: new FormControl('', { nonNullable: true }),
    rhFactor: new FormControl('', { nonNullable: true }),
    componentId: new FormControl<number | null>(null),
    areaId: new FormControl<number | null>(null),
    minQuantity: new FormControl<number | null>(null),
    freshOnly: new FormControl(true, { nonNullable: true }),
  });

  ngOnInit(): void {
    const query = this.route.snapshot.queryParamMap;
    this.filters.patchValue(
      {
        search: query.get('search') ?? '',
        aboGroup: query.get('aboGroup') ?? '',
        rhFactor: query.get('rhFactor') ?? '',
        componentId: query.get('componentId') ? Number(query.get('componentId')) : null,
        areaId: query.get('areaId') ? Number(query.get('areaId')) : null,
        minQuantity: query.get('minQuantity') ? Number(query.get('minQuantity')) : null,
        freshOnly: query.get('freshOnly') !== 'false',
      },
      { emitEvent: false },
    );
    const page = Number(query.get('page'));
    if (page > 0) this.page.set(page);

    this.lookupService
      .load()
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe((lookups) => {
        this.areas.set(lookups.areas ?? []);
        this.components.set(lookups.components ?? []);
      });

    this.filters.controls.search.valueChanges
      .pipe(debounceTime(300), distinctUntilChanged(), takeUntilDestroyed(this.destroyRef))
      .subscribe(() => this.applyFilters());
    merge(
      this.filters.controls.aboGroup.valueChanges,
      this.filters.controls.rhFactor.valueChanges,
      this.filters.controls.componentId.valueChanges,
      this.filters.controls.areaId.valueChanges,
      this.filters.controls.minQuantity.valueChanges,
      this.filters.controls.freshOnly.valueChanges,
    )
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe(() => this.applyFilters());
    this.reload();
  }

  protected hasFilters(): boolean {
    const value = this.filters.getRawValue();
    return !!(
      value.search.trim() ||
      value.aboGroup ||
      value.rhFactor ||
      value.componentId ||
      value.areaId ||
      value.minQuantity !== null
    ) || !value.freshOnly;
  }

  protected clearFilters(): void {
    this.filters.reset(
      { search: '', aboGroup: '', rhFactor: '', componentId: null, areaId: null, minQuantity: null, freshOnly: true },
      { emitEvent: false },
    );
    this.applyFilters();
  }

  protected onPage(event: PageEvent): void {
    this.page.set(event.pageIndex + 1);
    this.pageSize.set(event.pageSize);
    this.reload();
  }

  protected requestFor(item: BloodAvailability): void {
    const params = new URLSearchParams();
    if (item.aboGroup) params.set('aboGroup', item.aboGroup);
    if (item.rhFactor) params.set('rhFactor', item.rhFactor);
    if (item.componentId) params.set('componentId', String(item.componentId));
    if (item.areaId) params.set('areaId', String(item.areaId));
    const returnUrl = `/requests/new${params.size ? `?${params.toString()}` : ''}`;
    void this.router.navigate(this.isAuthenticated() ? ['/requests/new'] : ['/login'], {
      queryParams: this.isAuthenticated() ? Object.fromEntries(params.entries()) : { returnUrl },
    });
  }

  reload(): void {
    this.loadSub?.unsubscribe();
    this.state.set('loading');
    this.error.set('');
    const value = this.filters.getRawValue();
    const query: BloodSearchQuery = {
      aboGroup: value.aboGroup || null,
      rhFactor: value.rhFactor || null,
      componentId: value.componentId,
      areaId: value.areaId,
      search: value.search.trim() || null,
      freshOnly: value.freshOnly,
      minQuantity: value.minQuantity,
      page: this.page(),
      pageSize: this.pageSize(),
    };
    void this.router.navigate([], {
      relativeTo: this.route,
      replaceUrl: true,
      queryParams: {
        search: query.search,
        aboGroup: query.aboGroup,
        rhFactor: query.rhFactor,
        componentId: query.componentId,
        areaId: query.areaId,
        minQuantity: query.minQuantity,
        freshOnly: query.freshOnly === false ? false : null,
        page: query.page && query.page > 1 ? query.page : null,
      },
    });
    this.loadSub = this.publicApi
      .searchBlood(query)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (result) => {
          this.items.set(result.items ?? []);
          this.total.set(result.totalCount ?? 0);
          this.state.set(result.items?.length ? 'ready' : 'empty');
        },
        error: (error) => {
          this.items.set([]);
          this.total.set(0);
          this.error.set(publicErrorText(error));
          this.state.set('error');
        },
      });
  }

  private applyFilters(): void {
    this.page.set(1);
    this.reload();
  }
}
