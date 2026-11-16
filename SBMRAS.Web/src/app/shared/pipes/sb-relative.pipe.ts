import { Pipe, PipeTransform } from '@angular/core';

@Pipe({ name: 'sbRelative', standalone: true })
export class SbRelativePipe implements PipeTransform {
  transform(value: string | Date | null | undefined): string {
    if (!value) return 'Unknown';
    const time = new Date(value).getTime();
    if (Number.isNaN(time)) return 'Unknown';
    const minutes = Math.round((time - Date.now()) / 60_000);
    const absMinutes = Math.abs(minutes);
    const ago = minutes < 0;
    if (absMinutes < 1) return 'Just now';
    const amount = absMinutes < 60 ? `${absMinutes} min` :
      absMinutes < 1440 ? `${Math.round(absMinutes / 60)} hr` :
        `${Math.round(absMinutes / 1440)} day`;
    return ago ? `${amount} ago` : `in ${amount}`;
  }
}
