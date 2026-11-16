import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';

import { SessionService } from '../services/session.service';

export const permissionGuard: CanActivateFn = async (route) => {
  const session = inject(SessionService);
  const router = inject(Router);
  const permission = route.data['permission'] as string | undefined;
  const anyPermission = route.data['anyPermission'] as string[] | undefined;
  await session.load();
  const allowed = permission ? session.hasPermission(permission) : session.hasAnyPermission(anyPermission ?? []);
  return allowed ? true : router.createUrlTree(['/forbidden']);
};
