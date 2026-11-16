import { ChangeDetectionStrategy, Component, DestroyRef, OnInit, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { FormControl, FormGroup, ReactiveFormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { MatButtonModule } from '@angular/material/button';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatIconModule } from '@angular/material/icon';
import { MatInputModule } from '@angular/material/input';
import { MatSelectModule } from '@angular/material/select';

import { ViewState } from '../../../core/models/api.models';
import { PublicStats } from '../../../core/models/public.models';
import { AreaLookup } from '../../../core/models/lookup.models';
import { LookupService } from '../../../core/services/lookup.service';
import { PublicService, publicErrorText } from '../../../core/services/public.service';
import { StatePanel } from '../../../shared/components/state-panel';
import { SbRelativePipe } from '../../../shared/pipes/sb-relative.pipe';

@Component({
  selector: 'sb-landing',
  standalone: true,
  imports: [
    ReactiveFormsModule,
    RouterLink,
    MatButtonModule,
    MatFormFieldModule,
    MatIconModule,
    MatInputModule,
    MatSelectModule,
    StatePanel,
    SbRelativePipe,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './landing.html',
  styleUrl: './landing.scss',
})
export class Landing implements OnInit {
  private readonly publicApi = inject(PublicService);
  private readonly lookupService = inject(LookupService);
  private readonly router = inject(Router);
  private readonly destroyRef = inject(DestroyRef);

  protected readonly stats = signal<PublicStats | null>(null);
  protected readonly areas = signal<AreaLookup[]>([]);
  protected readonly state = signal<ViewState>('loading');
  protected readonly error = signal('');

  protected readonly searchForm = new FormGroup({
    search: new FormControl('', { nonNullable: true }),
    areaId: new FormControl<number | null>(null),
  });

  ngOnInit(): void {
    this.lookupService
      .load()
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe((lookups) => this.areas.set(lookups.areas ?? []));
    this.reload();
  }

  protected findBlood(): void {
    const value = this.searchForm.getRawValue();
    void this.router.navigate(['/find-blood'], {
      queryParams: { search: value.search.trim() || null, areaId: value.areaId },
    });
  }

  protected statValue(value: number | null | undefined, percent = false): string {
    if (value === null || value === undefined || !Number.isFinite(value)) {
      return 'Not reported';
    }
    return `${new Intl.NumberFormat().format(value)}${percent ? '%' : ''}`;
  }

  reload(): void {
    this.state.set('loading');
    this.error.set('');
    this.publicApi
      .getStats()
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (stats) => {
          this.stats.set(stats);
          this.state.set('ready');
        },
        error: (error) => {
          this.stats.set(null);
          this.error.set(publicErrorText(error));
          this.state.set('error');
        },
      });
  }
}
