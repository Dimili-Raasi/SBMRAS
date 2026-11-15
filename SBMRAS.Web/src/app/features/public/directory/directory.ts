import { ChangeDetectionStrategy, Component, DestroyRef, OnInit, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { FormControl, FormGroup, ReactiveFormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { MatButtonModule } from '@angular/material/button';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatIconModule } from '@angular/material/icon';
import { MatInputModule } from '@angular/material/input';
import { MatPaginatorModule, PageEvent } from '@angular/material/paginator';
import { MatSelectModule } from '@angular/material/select';
import { Subscription, debounceTime, distinctUntilChanged, merge } from 'rxjs';

import { ViewState } from '../../../core/models/api.models';
import { AreaLookup } from '../../../core/models/lookup.models';
import { FacilitySearchQuery, PublicFacility } from '../../../core/models/public.models';
import { LookupService } from '../../../core/services/lookup.service';
import { PublicService, publicErrorText } from '../../../core/services/public.service';
import { QualityGauge } from '../../../shared/components/quality-gauge';
import { PageHeader } from '../../../shared/components/page-header';
import { StatePanel } from '../../../shared/components/state-panel';
import { SbRelativePipe } from '../../../shared/pipes/sb-relative.pipe';

@Component({
  selector: 'sb-directory',
  standalone: true,
  imports: [
    ReactiveFormsModule,
    MatButtonModule,
    MatFormFieldModule,
    MatIconModule,
    MatInputModule,
    MatPaginatorModule,
    MatSelectModule,
    PageHeader,
    QualityGauge,
    StatePanel,
    SbRelativePipe,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './directory.html',
  styleUrl: './directory.scss',
})
export class Directory implements OnInit {
  private readonly publicApi = inject(PublicService);
  private readonly lookupService = inject(LookupService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly destroyRef = inject(DestroyRef);

  protected readonly items = signal<PublicFacility[]>([]);
  protected readonly areas = signal<AreaLookup[]>([]);
  protected readonly state = signal<ViewState>('loading');
  protected readonly error = signal('');
  protected readonly total = signal(0);
  protected readonly page = signal(1);
  protected readonly pageSize = signal(12);
  private loadSub?: Subscription;

  protected readonly filters = new FormGroup({
    search: new FormControl('', { nonNullable: true }),
    facilityType: new FormControl('', { nonNullable: true }),
    areaId: new FormControl<number | null>(null),
  });

  ngOnInit(): void {
    const query = this.route.snapshot.queryParamMap;
    this.filters.patchValue(
      {
        search: query.get('search') ?? '',
        facilityType: query.get('facilityType') ?? '',
        areaId: query.get('areaId') ? Number(query.get('areaId')) : null,
      },
      { emitEvent: false },
    );
    const page = Number(query.get('page'));
    if (page > 0) this.page.set(page);

    this.lookupService
      .load()
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe((lookups) => this.areas.set(lookups.areas ?? []));

    this.filters.controls.search.valueChanges
      .pipe(debounceTime(300), distinctUntilChanged(), takeUntilDestroyed(this.destroyRef))
      .subscribe(() => this.applyFilters());
    merge(this.filters.controls.facilityType.valueChanges, this.filters.controls.areaId.valueChanges)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe(() => this.applyFilters());
    this.reload();
  }

  protected hasFilters(): boolean {
    const value = this.filters.getRawValue();
    return !!(value.search.trim() || value.facilityType || value.areaId);
  }

  protected clearFilters(): void {
    this.filters.reset({ search: '', facilityType: '', areaId: null }, { emitEvent: false });
    this.applyFilters();
  }

  protected onPage(event: PageEvent): void {
    this.page.set(event.pageIndex + 1);
    this.pageSize.set(event.pageSize);
    this.reload();
  }

  protected contact(facility: PublicFacility): void {
    if (facility.contactPhone) {
      window.location.href = `tel:${facility.contactPhone}`;
    } else if (facility.contactEmail) {
      window.location.href = `mailto:${facility.contactEmail}`;
    }
  }

  reload(): void {
    this.loadSub?.unsubscribe();
    this.state.set('loading');
    this.error.set('');
    const value = this.filters.getRawValue();
    const query: FacilitySearchQuery = {
      facilityType: value.facilityType || null,
      areaId: value.areaId,
      search: value.search.trim() || null,
      page: this.page(),
      pageSize: this.pageSize(),
    };
    void this.router.navigate([], {
      relativeTo: this.route,
      replaceUrl: true,
      queryParams: {
        facilityType: query.facilityType,
        areaId: query.areaId,
        search: query.search,
        page: query.page && query.page > 1 ? query.page : null,
      },
    });
    this.loadSub = this.publicApi
      .searchFacilities(query)
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
