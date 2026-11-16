import { Injectable, inject, signal } from '@angular/core';
import { Observable, catchError, of, shareReplay, tap } from 'rxjs';

import { EMPTY_LOOKUPS, Lookups } from '../models/lookup.models';
import { ApiService } from './api.service';

@Injectable({ providedIn: 'root' })
export class LookupService {
  private readonly api = inject(ApiService);
  private cache$: Observable<Lookups> | null = null;
  readonly data = signal<Lookups>(EMPTY_LOOKUPS);

  load(force = false): Observable<Lookups> {
    if (!this.cache$ || force) {
      this.cache$ = this.api.get<Lookups>('public/lookups').pipe(
        catchError(() => of(EMPTY_LOOKUPS)),
        tap((lookups) => this.data.set({ ...EMPTY_LOOKUPS, ...lookups })),
        shareReplay({ bufferSize: 1, refCount: false }),
      );
    }
    return this.cache$;
  }

  set(value: Lookups): void {
    this.data.set({ ...EMPTY_LOOKUPS, ...value });
  }
}
