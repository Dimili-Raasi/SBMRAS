export interface ApiResponse<T> {
  success: boolean;
  message: string;
  data: T | null;
  errors: string[];
}

export interface PagedResult<T> {
  items: T[];
  totalCount: number;
  page: number;
  pageSize: number;
}

export type QueryParams = Record<string, string | number | boolean | null | undefined | Date>;

export type ViewState = 'loading' | 'empty' | 'error' | 'ready';
