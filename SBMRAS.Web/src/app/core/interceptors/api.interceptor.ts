import { HttpErrorResponse, HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { catchError, finalize, from, switchMap, throwError } from 'rxjs';

import { environment } from '../../../environments/environment';
import { ApiError } from '../utils/api-error';
import { newGuid } from '../utils/http.util';
import { AuthService } from '../services/auth.service';
import { LoadingService } from '../services/loading.service';
import { UiService } from '../services/ui.service';

export const apiInterceptor: HttpInterceptorFn = (request, next) => {
  const auth = inject(AuthService);
  const loading = inject(LoadingService);
  const ui = inject(UiService);
  const origin = typeof location === 'undefined' ? 'http://localhost' : location.origin;
  const apiBase = new URL(environment.apiBaseUrl, origin);
  const requestUrl = new URL(request.url, origin);
  const apiBasePath = apiBase.pathname.replace(/\/$/, '');
  const isApiRequest = requestUrl.origin === apiBase.origin &&
    (requestUrl.pathname === apiBasePath || requestUrl.pathname.startsWith(`${apiBasePath}/`));
  loading.begin();

  const url = !/^(https?:)?\/\//i.test(request.url) && !request.url.startsWith('/') && !request.url.startsWith('assets/')
    ? `${environment.apiBaseUrl.replace(/\/$/, '')}/${request.url.replace(/^\//, '')}`
    : request.url;
  const baseRequest = request.clone({
    url,
    setHeaders: { 'X-Correlation-Id': request.headers.get('X-Correlation-Id') ?? newGuid() },
  });

  const withAuth = isApiRequest && !request.url.endsWith('/auth/config')
    ? from(auth.authorizationHeaders()).pipe(
        switchMap((headers) => next(headers['Authorization']
          ? baseRequest.clone({ setHeaders: headers })
          : baseRequest)),
      )
    : next(baseRequest);

  return withAuth.pipe(
    catchError((error: unknown) => {
      if (error instanceof HttpErrorResponse) {
        const body = error.error as { message?: string; errors?: string[] } | null;
        const apiError = new ApiError(
          body?.message || error.message || 'The request could not be completed.',
          error.status,
          Array.isArray(body?.errors) ? body.errors : [],
        );
        if (error.status === 0 || error.status >= 500) ui.error(apiError.message);
        return throwError(() => apiError);
      }
      return throwError(() => error);
    }),
    finalize(() => loading.end()),
  );
};
