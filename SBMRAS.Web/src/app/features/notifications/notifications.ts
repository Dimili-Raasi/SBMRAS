import { ChangeDetectionStrategy, Component, DestroyRef, OnInit, computed, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { Router } from '@angular/router';
import { MatButtonModule } from '@angular/material/button';
import { MatButtonToggleModule } from '@angular/material/button-toggle';
import { MatIconModule } from '@angular/material/icon';
import { MatPaginatorModule, PageEvent } from '@angular/material/paginator';
import { MatTooltipModule } from '@angular/material/tooltip';
import { Subscription } from 'rxjs';

import { ViewState } from '../../core/models/api.models';
import { AppNotification } from '../../core/models/notifications.models';
import { NotificationsService } from '../../core/services/notifications.service';
import { UiService } from '../../core/services/ui.service';
import { errorMessage } from '../../core/utils/api-error';
import { PageHeader } from '../../shared/components/page-header';
import { StatePanel } from '../../shared/components/state-panel';
import { SbDatePipe } from '../../shared/pipes/sb-date.pipe';
import { SbRelativePipe } from '../../shared/pipes/sb-relative.pipe';

const TYPE_ICONS: Record<string, string> = {
  Info: 'info',
  Success: 'check_circle',
  Warning: 'warning',
  Action: 'assignment_late',
};

/** /notifications — in-app notification inbox (contract §6 Notifications). */
@Component({
  selector: 'sb-notifications',
  imports: [
    MatButtonModule,
    MatButtonToggleModule,
    MatIconModule,
    MatPaginatorModule,
    MatTooltipModule,
    PageHeader,
    StatePanel,
    SbDatePipe,
    SbRelativePipe,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './notifications.html',
  styleUrl: './notifications.scss',
})
export class Notifications implements OnInit {
  private readonly notifications = inject(NotificationsService);
  private readonly ui = inject(UiService);
  private readonly router = inject(Router);
  private readonly destroyRef = inject(DestroyRef);

  protected readonly state = signal<ViewState>('loading');
  protected readonly error = signal('');
  protected readonly items = signal<AppNotification[]>([]);
  protected readonly total = signal(0);
  protected readonly page = signal(1);
  protected readonly pageSize = signal(20);
  protected readonly unreadOnly = signal(false);
  protected readonly busyIds = signal<ReadonlySet<number>>(new Set());
  protected readonly markingAll = signal(false);

  protected readonly hasUnread = computed(() => this.items().some((n) => !n.isRead));

  private loadSub?: Subscription;

  ngOnInit(): void {
    this.reload();
  }

  protected icon(type: string): string {
    return TYPE_ICONS[type] ?? 'notifications';
  }

  protected setFilter(unreadOnly: boolean): void {
    if (unreadOnly === this.unreadOnly()) {
      return;
    }
    this.unreadOnly.set(unreadOnly);
    this.page.set(1);
    this.reload();
  }

  protected onPage(event: PageEvent): void {
    this.page.set(event.pageIndex + 1);
    this.pageSize.set(event.pageSize);
    this.reload();
  }

  reload(): void {
    this.loadSub?.unsubscribe();
    this.state.set('loading');
    this.error.set('');
    this.loadSub = this.notifications
      .list({ unreadOnly: this.unreadOnly(), page: this.page(), pageSize: this.pageSize() })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (result) => {
          this.items.set(result.items);
          this.total.set(result.totalCount);
          this.state.set(result.items.length ? 'ready' : 'empty');
        },
        error: (err) => {
          this.items.set([]);
          this.error.set(errorMessage(err, 'Notifications could not be loaded.'));
          this.state.set('error');
        },
      });
  }

  protected open(n: AppNotification): void {
    if (!n.isRead) {
      this.markRead(n, false);
    }
    if (n.route) {
      this.router.navigateByUrl(n.route);
    }
  }

  protected markRead(n: AppNotification, notify = true, event?: Event): void {
    event?.stopPropagation();
    if (n.isRead || this.busyIds().has(n.notificationId)) {
      return;
    }
    this.setBusy(n.notificationId, true);
    this.notifications
      .markRead(n.notificationId)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: () => {
          this.setBusy(n.notificationId, false);
          if (this.unreadOnly()) {
            this.items.update((list) => list.filter((x) => x.notificationId !== n.notificationId));
            this.total.update((t) => Math.max(0, t - 1));
            if (!this.items().length) {
              this.state.set('empty');
            }
          } else {
            this.items.update((list) =>
              list.map((x) => (x.notificationId === n.notificationId ? { ...x, isRead: true } : x)),
            );
          }
          if (notify) {
            this.ui.success('Marked as read.');
          }
        },
        error: (err) => {
          this.setBusy(n.notificationId, false);
          this.ui.error(errorMessage(err, 'Could not mark the notification as read.'));
        },
      });
  }

  protected markAllRead(): void {
    if (this.markingAll()) {
      return;
    }
    this.markingAll.set(true);
    this.notifications
      .markAllRead()
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: () => {
          this.markingAll.set(false);
          this.ui.success('All notifications marked as read.');
          if (this.unreadOnly()) {
            this.page.set(1);
            this.reload();
          } else {
            this.items.update((list) => list.map((x) => ({ ...x, isRead: true })));
          }
        },
        error: (err) => {
          this.markingAll.set(false);
          this.ui.error(errorMessage(err, 'Could not mark all notifications as read.'));
        },
      });
  }

  private setBusy(id: number, busy: boolean): void {
    this.busyIds.update((set) => {
      const next = new Set(set);
      if (busy) {
        next.add(id);
      } else {
        next.delete(id);
      }
      return next;
    });
  }
}
