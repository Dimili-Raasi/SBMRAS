import { ChangeDetectionStrategy, Component, input } from '@angular/core';

@Component({
  selector: 'sb-blood-group-tile',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<span class="blood-group" [class.large]="size() === 'large' || size() === 'lg'" [class.small]="size() === 'sm'">{{ label() }}</span>`,
  styles: [`
    .blood-group { display:inline-flex; min-width:2.6rem; min-height:2rem; align-items:center; justify-content:center; padding:.2rem .45rem; border:1px solid #c8102e; border-radius:7px; color:#a50c25; background:#fff8f8; font:700 .95rem 'IBM Plex Mono',monospace }
    .large { min-width:3.4rem; min-height:2.6rem; font-size:1.2rem } .small { min-width:2rem; min-height:1.6rem; font-size:.8rem }
  `],
})
export class BloodGroupTile {
  readonly aboGroup = input('');
  readonly rhFactor = input('');
  readonly size = input<'small' | 'medium' | 'large' | 'sm' | 'md' | 'lg'>('medium');
  label(): string {
    const rh = this.rhFactor() === 'Positive' || this.rhFactor() === '+' ? '+' :
      this.rhFactor() === 'Negative' || this.rhFactor() === '-' ? '−' : '';
    return this.aboGroup() ? `${this.aboGroup()}${rh}` : '—';
  }
}
