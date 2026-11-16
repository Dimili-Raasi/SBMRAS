import { HttpParams } from '@angular/common/http';

/** Builds HttpParams skipping null/undefined/'' values; Dates become ISO strings. */
export function toHttpParams(query?: object | null): HttpParams {
  let params = new HttpParams();
  if (!query) {
    return params;
  }
  for (const [key, value] of Object.entries(query)) {
    if (value === null || value === undefined || value === '') {
      continue;
    }
    params = params.set(key, value instanceof Date ? value.toISOString() : String(value));
  }
  return params;
}

/** True for endpoint paths like `public/stats` that should be prefixed with environment.apiBaseUrl. */
export function isRelativeApiPath(url: string): boolean {
  return !/^(https?:)?\/\//i.test(url) && !url.startsWith('/') && !url.startsWith('assets/');
}

export function fileNameFromDisposition(header: string | null, fallback: string): string {
  if (!header) {
    return fallback;
  }
  const match = /filename\*?=(?:UTF-8'')?"?([^";]+)"?/i.exec(header);
  return match ? decodeURIComponent(match[1]) : fallback;
}

export function saveBlob(blob: Blob, fileName: string): void {
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = fileName;
  anchor.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

export function newGuid(): string {
  return typeof crypto !== 'undefined' && 'randomUUID' in crypto
    ? crypto.randomUUID()
    : `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
}

/** 'O' + 'Positive' → 'O+'. */
export function bloodGroupLabel(aboGroup?: string | null, rhFactor?: string | null): string {
  if (!aboGroup) {
    return '—';
  }
  const rh = rhFactor === 'Positive' || rhFactor === '+' ? '+' : rhFactor === 'Negative' || rhFactor === '-' ? '−' : '';
  return `${aboGroup}${rh}`;
}
