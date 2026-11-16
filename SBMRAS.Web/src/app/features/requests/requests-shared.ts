// Shared helpers for the request/coordination screens.
import { ApiError } from '../../core/utils/api-error';
import { REQUEST_STATUS_LABELS, RequestStatus } from '../../core/models/requests.models';

/** Maps API failures to a user-facing banner message (400 validation, 403, 404, 409 conflicts). */
export function requestErrorText(error: unknown): string {
  if (error instanceof ApiError) {
    const details = error.errors?.length ? ` ${error.errors.join(' ')}` : '';
    switch (error.status) {
      case 0:
        return 'The SBMRAS service is unreachable. Check your connection and try again.';
      case 400:
        return `${error.message || 'Please correct the highlighted fields.'}${details}`;
      case 403:
        return error.message || 'You do not have permission to perform this action.';
      case 404:
        return error.message || 'The request no longer exists or you cannot view it.';
      case 409:
        return error.message || 'The request was changed by someone else. Reload and try again.';
      default:
        return `${error.message || 'The request failed.'}${details}`;
    }
  }
  return error instanceof Error && error.message ? error.message : 'Something went wrong. Please try again.';
}

export function isConflict(error: unknown): boolean {
  return error instanceof ApiError && error.status === 409;
}

export function statusLabel(status: string | null | undefined): string {
  return status ? (REQUEST_STATUS_LABELS[status] ?? status) : 'Not reported';
}

/** SLA emphasis for the coordination queue based on needed-by time. */
export type SlaLevel = 'overdue' | 'due-soon' | 'ok' | 'none';

export function slaLevel(neededBy: string | null | undefined, status: string, now = Date.now()): SlaLevel {
  if (!neededBy || ['Fulfilled', 'Closed', 'Cancelled'].includes(status)) {
    return 'none';
  }
  const due = new Date(neededBy).getTime();
  if (Number.isNaN(due)) {
    return 'none';
  }
  const hours = (due - now) / 3_600_000;
  if (hours < 0) {
    return 'overdue';
  }
  return hours <= 6 ? 'due-soon' : 'ok';
}

export function slaText(neededBy: string | null | undefined, now = Date.now()): string {
  if (!neededBy) {
    return 'Not reported';
  }
  const diffMin = Math.round((new Date(neededBy).getTime() - now) / 60_000);
  const abs = Math.abs(diffMin);
  const span =
    abs < 60 ? `${abs} min` : abs < 2880 ? `${Math.round(abs / 60)} h` : `${Math.round(abs / 1440)} d`;
  return diffMin < 0 ? `Overdue by ${span}` : `Due in ${span}`;
}

/** Labels/icons/reason requirements for coordination actions, keyed by target status. */
export interface TransitionAction {
  toStatus: RequestStatus;
  label: string;
  icon: string;
  tone: 'primary' | 'neutral' | 'danger';
  reasonRequired: boolean;
  reasonLabel: string;
  title: string;
}

export const TRANSITION_ACTIONS: Record<RequestStatus, TransitionAction> = {
  Submitted: {
    toStatus: 'Submitted',
    label: 'Reopen',
    icon: 'restart_alt',
    tone: 'neutral',
    reasonRequired: true,
    reasonLabel: 'Why is this request being reopened?',
    title: 'Reopen request',
  },
  UnderReview: {
    toStatus: 'UnderReview',
    label: 'Start review',
    icon: 'fact_check',
    tone: 'primary',
    reasonRequired: false,
    reasonLabel: 'Review note (optional)',
    title: 'Start review',
  },
  Matched: {
    toStatus: 'Matched',
    label: 'Match to facility',
    icon: 'join_inner',
    tone: 'primary',
    reasonRequired: false,
    reasonLabel: 'Match note (optional)',
    title: 'Match to facility',
  },
  Contacted: {
    toStatus: 'Contacted',
    label: 'Mark contacted',
    icon: 'call',
    tone: 'primary',
    reasonRequired: false,
    reasonLabel: 'Contact note (optional)',
    title: 'Mark as contacted',
  },
  Fulfilled: {
    toStatus: 'Fulfilled',
    label: 'Report fulfilled',
    icon: 'task_alt',
    tone: 'primary',
    reasonRequired: false,
    reasonLabel: 'Fulfilment note (optional)',
    title: 'Report fulfilment',
  },
  UnableToFulfil: {
    toStatus: 'UnableToFulfil',
    label: 'Unable to fulfil',
    icon: 'block',
    tone: 'danger',
    reasonRequired: true,
    reasonLabel: 'Reason the request cannot be fulfilled',
    title: 'Unable to fulfil',
  },
  Closed: {
    toStatus: 'Closed',
    label: 'Close',
    icon: 'archive',
    tone: 'neutral',
    reasonRequired: true,
    reasonLabel: 'Closing note',
    title: 'Close request',
  },
  Cancelled: {
    toStatus: 'Cancelled',
    label: 'Cancel request',
    icon: 'cancel',
    tone: 'danger',
    reasonRequired: true,
    reasonLabel: 'Cancellation reason',
    title: 'Cancel request',
  },
};
