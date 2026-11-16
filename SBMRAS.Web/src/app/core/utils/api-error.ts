/** Error thrown by ApiService / interceptors for every failed API call. */
export class ApiError extends Error {
  constructor(
    message: string,
    public readonly status: number,
    public readonly errors: string[] = [],
  ) {
    super(message);
    this.name = 'ApiError';
  }
}

/** Friendly message for any error value (ApiError, Error, string). */
export function errorMessage(error: unknown, fallback = 'Something went wrong. Please try again.'): string {
  if (error instanceof ApiError) {
    return error.errors.length ? `${error.message} ${error.errors.join(' ')}` : error.message;
  }
  if (error instanceof Error && error.message) {
    return error.message;
  }
  return typeof error === 'string' && error ? error : fallback;
}

export const API_UNREACHABLE_MESSAGE =
  'The SBMRAS service is unreachable. Check that the API is running and try again.';
