import { Injectable, inject } from '@angular/core';
import { Observable, map, tap } from 'rxjs';

import { PagedResult } from '../models/api.models';
import { AppNotification, NotificationQuery } from '../models/notifications.models';
import { ApiService } from './api.service';
import { NotificationBadgeService } from './notification-badge.service';

/** In-app notification endpoints (contract §6 Notifications). Keeps the header badge in sync. */
@Injectable({ providedIn: 'root' })
export class NotificationsService {
  private readonly api = inject(ApiService);
  private readonly badge = inject(NotificationBadgeService);

  list(query: NotificationQuery): Observable<PagedResult<AppNotification>> {
    return this.api
      .get<PagedResult<AppNotification>>('notifications', { ...query })
      .pipe(map((page) => ({ ...page, items: page?.items ?? [], totalCount: page?.totalCount ?? 0 })));
  }

  unreadCount(): Observable<number> {
    return this.api.get<{ count: number }>('notifications/unread-count').pipe(map((r) => r?.count ?? 0));
  }

  markRead(notificationId: number): Observable<unknown> {
    return this.api.post<unknown>(`notifications/${notificationId}/read`).pipe(tap(() => this.badge.refresh()));
  }

  markAllRead(): Observable<unknown> {
    return this.api.post<unknown>('notifications/read-all').pipe(tap(() => this.badge.refresh()));
  }
}
