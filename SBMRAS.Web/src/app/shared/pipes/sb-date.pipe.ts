import { DatePipe } from '@angular/common';
import { Pipe, PipeTransform } from '@angular/core';

@Pipe({ name: 'sbDate', standalone: true })
export class SbDatePipe implements PipeTransform {
  private readonly datePipe = new DatePipe('en');
  transform(value: string | Date | null | undefined, format = 'mediumDate'): string {
    if (!value) return '—';
    return this.datePipe.transform(value, format) ?? '—';
  }
}
