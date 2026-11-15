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
import { AreaLookup, ResourceCategoryLookup, ResourceTypeLookup } from '../../../core/models/lookup.models';
import { ResourceAvailability, ResourceSearchQuery } from '../../../core/models/public.models';
import { LookupService } from '../../../core/services/lookup.service';
import { PublicService, publicErrorText } from '../../../core/services/public.service';
import { FreshnessBadge } from '../../../shared/components/freshness-badge';
import { PageHeader } from '../../../shared/components/page-header';
import { StatePanel } from '../../../shared/components/state-panel';
import { StatusChip } from '../../../shared/components/status-chip';
import { SbQtyPipe } from '../../../shared/pipes/sb-qty.pipe';

@Component({
  selector: 'sb-find-resources',
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
    FreshnessBadge,
    PageHeader,
    StatePanel,
    StatusChip,
    SbQtyPipe,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './find-resources.html',
  styleUrl: './find-resources.scss',
})
export class FindResources implements OnInit {
  private readonly publicApi = inject(PublicService);
  private readonly lookupService = inject(LookupService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly destroyRef = inject(DestroyRef);

  protected readonly items = signal<ResourceAvailability[]>([]);
  protected readonly areas = signal<AreaLookup[]>([]);
  protected readonly categories = signal<ResourceCategoryLookup[]>([]);
  protected readonly resourceTypes = signal<ResourceTypeLookup[]>([]);
  protected readonly state = signal<ViewState>('loading');
  protected readonly error = signal('');
  protected readonly total = signal(0);
  protected readonly page = signal(1);
  protected readonly pageSize = signal(12);
  private loadSub?: Subscription;

  protected readonly filters = new FormGroup({
    search: new FormControl('', { nonNullable: true }),
    categoryId: new FormControl<number | null>(null),
    resourceTypeId: new FormControl<number | null>(null),
    areaId: new FormControl<number | null>(null),
    availableOnly: new FormControl(false, { nonNullable: true }),
    freshOnly: new FormControl(true, { nonNullable: true }),
  });

  ngOnInit(): void {
    const query = this.route.snapshot.queryParamMap;
    this.filters.patchValue(
      {
        search: query.get('search') ?? '',
        categoryId: query.get('categoryId') ? Number(query.get('categoryId')) : null,
        resourceTypeId: query.get('resourceTypeId') ? Number(query.get('resourceTypeId')) : null,
        areaId: query.get('areaId') ? Number(query.get('areaId')) : null,
        availableOnly: query.get('availableOnly') === 'true',
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
        this.categories.set(lookups.resourceCategories ?? []);
        this.resourceTypes.set(lookups.resourceTypes ?? []);
      });

    this.filters.controls.search.valueChanges
      .pipe(debounceTime(300), distinctUntilChanged(), takeUntilDestroyed(this.destroyRef))
      .subscribe(() => this.applyFilters());
    merge(
      this.filters.controls.categoryId.valueChanges,
      this.filters.controls.resourceTypeId.valueChanges,
      this.filters.controls.areaId.valueChanges,
      this.filters.controls.availableOnly.valueChanges,
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
      value.categoryId ||
      value.resourceTypeId ||
      value.areaId ||
      value.availableOnly
    ) || !value.freshOnly;
  }

  protected filteredResourceTypes(): ResourceTypeLookup[] {
    const categoryId = this.filters.controls.categoryId.value;
    return categoryId
      ? this.resourceTypes().filter((type) => type.categoryId === categoryId)
      : this.resourceTypes();
  }

  protected clearFilters(): void {
    this.filters.reset(
      { search: '', categoryId: null, resourceTypeId: null, areaId: null, availableOnly: false, freshOnly: true },
      { emitEvent: false },
    );
    this.applyFilters();
  }

  protected onPage(event: PageEvent): void {
    this.page.set(event.pageIndex + 1);
    this.pageSize.set(event.pageSize);
    this.reload();
  }

  protected contactFacility(item: ResourceAvailability): void {
    if (item.contactPhone) {
      window.location.href = `tel:${item.contactPhone}`;
    } else {
      void this.router.navigate(['/directory'], { queryParams: { search: item.facilityName } });
    }
  }

  reload(): void {
    this.loadSub?.unsubscribe();
    this.state.set('loading');
    this.error.set('');
    const value = this.filters.getRawValue();
    const query: ResourceSearchQuery = {
      categoryId: value.categoryId,
      resourceTypeId: value.resourceTypeId,
      areaId: value.areaId,
      search: value.search.trim() || null,
      availableOnly: value.availableOnly,
      freshOnly: value.freshOnly,
      page: this.page(),
      pageSize: this.pageSize(),
    };
    void this.router.navigate([], {
      relativeTo: this.route,
      replaceUrl: true,
      queryParams: {
        search: query.search,
        categoryId: query.categoryId,
        resourceTypeId: query.resourceTypeId,
        areaId: query.areaId,
        availableOnly: query.availableOnly === true ? true : null,
        freshOnly: query.freshOnly === false ? false : null,
        page: query.page && query.page > 1 ? query.page : null,
      },
    });
    this.loadSub = this.publicApi
      .searchResources(query)
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
