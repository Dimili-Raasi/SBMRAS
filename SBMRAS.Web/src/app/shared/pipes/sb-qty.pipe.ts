import { Pipe, PipeTransform } from '@angular/core';

@Pipe({ name: 'sbQty', standalone: true })
export class SbQtyPipe implements PipeTransform {
  transform(value: number | null | undefined, unit?: string | null): string {
    if (value === null || value === undefined || !Number.isFinite(value)) return 'Not reported';
    return `${new Intl.NumberFormat('en', { maximumFractionDigits: 2 }).format(value)}${unit ? ` ${unit}` : ''}`;
  }
}
