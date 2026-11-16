import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, map } from 'rxjs';

import { environment } from '../../../environments/environment';
import { ApiResponse, PagedResult, QueryParams } from '../models/api.models';
import { ApiError } from '../utils/api-error';
import { fileNameFromDisposition, toHttpParams } from '../utils/http.util';

@Injectable({ providedIn: 'root' })
export class ApiService {
  private readonly http = inject(HttpClient);

  get<T>(url: string, params?: QueryParams | object | null): Observable<T> {
    return this.http
      .get<unknown>(this.resolveUrl(url), { params: toHttpParams(params) })
      .pipe(map((body) => this.unwrap<T>(body)));
  }

  getPaged<T>(url: string, params?: QueryParams | object | null): Observable<PagedResult<T>> {
    return this.get<PagedResult<T>>(url, params);
  }

  post<T>(url: string, body?: unknown, headers?: Record<string, string>): Observable<T> {
    return this.http
      .post<unknown>(this.resolveUrl(url), body ?? {}, { headers: new HttpHeaders(headers) })
      .pipe(map((response) => this.unwrap<T>(response)));
  }

  put<T>(url: string, body?: unknown, headers?: Record<string, string>): Observable<T> {
    return this.http
      .put<unknown>(this.resolveUrl(url), body ?? {}, { headers: new HttpHeaders(headers) })
      .pipe(map((response) => this.unwrap<T>(response)));
  }

  download(url: string, params: QueryParams | object | null, fileName: string): Observable<Blob> {
    return this.http
      .get(this.resolveUrl(url), { params: toHttpParams(params), observe: 'response', responseType: 'blob' })
      .pipe(
        map((response) => {
          const blob = response.body ?? new Blob();
          const name = fileNameFromDisposition(response.headers.get('content-disposition'), fileName);
          const anchor = document.createElement('a');
          const objectUrl = URL.createObjectURL(blob);
          anchor.href = objectUrl;
          anchor.download = name;
          anchor.click();
          setTimeout(() => URL.revokeObjectURL(objectUrl), 1000);
          return blob;
        }),
      );
  }

  private resolveUrl(url: string): string {
    if (/^(https?:)?\/\//i.test(url) || url.startsWith('assets/')) {
      return url;
    }
    if (url.startsWith('/')) {
      return url;
    }
    return `${environment.apiBaseUrl.replace(/\/$/, '')}/${url.replace(/^\//, '')}`;
  }

  private unwrap<T>(body: unknown): T {
    if (body && typeof body === 'object' && 'success' in body && 'data' in body) {
      const envelope = body as ApiResponse<T>;
      if (!envelope.success) {
        throw new ApiError(
          envelope.message || 'The request could not be completed.',
          0,
          Array.isArray(envelope.errors) ? envelope.errors : [],
        );
      }
      return envelope.data as T;
    }
    return body as T;
  }
}
