import { Injectable, signal } from '@angular/core';

@Injectable({ providedIn: 'root' })
export class LoadingService {
  private readonly pending = signal(0);
  readonly isLoading = signal(false);

  begin(): void {
    this.pending.update((count) => count + 1);
    this.isLoading.set(true);
  }

  end(): void {
    this.pending.update((count) => {
      const next = Math.max(0, count - 1);
      this.isLoading.set(next > 0);
      return next;
    });
  }
}
