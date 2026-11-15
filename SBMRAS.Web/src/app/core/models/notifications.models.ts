export type NotificationType = 'Info' | 'Success' | 'Warning' | 'Action';

export interface AppNotification {
  notificationId: number;
  title: string;
  message: string;
  type: NotificationType;
  entityType: string | null;
  entityId: string | null;
  route: string | null;
  isRead: boolean;
  createdAt: string;
}

export interface NotificationQuery {
  unreadOnly?: boolean;
  page?: number;
  pageSize?: number;
}

export interface UnreadCount {
  count: number;
}
