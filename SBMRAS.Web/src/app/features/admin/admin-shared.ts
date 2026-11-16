import { ApiError } from '../../core/utils/api-error';
// Shared building blocks used by every admin screen (paths per AGENTS_WEB_GUIDE.md).
import { HasPermissionDirective } from '../../core/directives/has-permission.directive';
import { PageHeader } from '../../shared/components/page-header';
import { StatePanel } from '../../shared/components/state-panel';

export const adminShared = [PageHeader, StatePanel, HasPermissionDirective] as const;

export const ADMIN_ROLE_OPTIONS: { code: string; name: string; hint: string }[] = [
  { code: 'PublicUser', name: 'Public User', hint: 'Always granted' },
  { code: 'HospitalManagement', name: 'Hospital Management', hint: 'Hospital inventory & requests' },
  { code: 'BloodBank', name: 'Blood Bank', hint: 'Blood stock & requests' },
  { code: 'Admin', name: 'Administrator', hint: 'Full administration' },
];

export function roleName(code: string): string {
  return ADMIN_ROLE_OPTIONS.find((r) => r.code === code)?.name ?? code;
}

/** Maps API failures to a form-level banner message (400 validation errors, 409 conflicts, 403/404). */
export function serverErrorText(error: unknown): string {
  if (error instanceof ApiError) {
    const details = error.errors?.length ? ` ${error.errors.join(' ')}` : '';
    switch (error.status) {
      case 0:
        return 'The SBMRAS service is unreachable. Check your connection and try again.';
      case 403:
        return error.message || 'You do not have permission to perform this action.';
      case 404:
        return error.message || 'The record no longer exists. Reload and try again.';
      case 409:
        return error.message || 'The record was changed by someone else. Reload and try again.';
      default:
        return `${error.message || 'The request failed.'}${details}`;
    }
  }
  return error instanceof Error && error.message ? error.message : 'Something went wrong. Please try again.';
}

export function isConflict(error: unknown): boolean {
  return error instanceof ApiError && error.status === 409;
}
