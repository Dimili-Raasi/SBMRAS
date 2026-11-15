import { Injectable, inject, signal } from '@angular/core';
import { firstValueFrom } from 'rxjs';

import { ApiService } from './api.service';
import { SessionService } from './session.service';

@Injectable({ providedIn: 'root' })
export class NotificationBadgeService {
  private readonly api = inject(ApiService);
  private readonly session = inject(SessionService);
  readonly count = signal(0);

  async refresh(): Promise<void> {
    if (!this.session.isAuthenticated()) {
      this.count.set(0);
      return;
    }
    try {
      const result = await firstValueFrom(this.api.get<{ count: number }>('notifications/unread-count'));
      this.count.set(Math.max(0, result?.count ?? 0));
    } catch {
      this.count.set(0);
    }
  }
}
