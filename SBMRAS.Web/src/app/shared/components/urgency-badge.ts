import { ChangeDetectionStrategy, Component, input } from '@angular/core';

@Component({
  selector: 'sb-urgency-badge',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<span class="urgency" [class]="className()"><i></i>{{ urgency() || 'Routine' }}</span>`,
  styles: [`
    .urgency { display:inline-flex; align-items:center; gap:.4rem; color:#596979; font-size:.78rem; font-weight:700 }
    i { width:8px; height:8px; border-radius:50%; background:#98a3ad } .urgent i { background:#f2a900 }
    .emergency { color:#b91c31 } .emergency i { background:#d93025; box-shadow:0 0 0 3px #ffdfe3; animation:pulse 1.8s infinite }
    @keyframes pulse { 50% { box-shadow:0 0 0 6px #ffecef } }
  `],
})
export class UrgencyBadge {
  readonly urgency = input<string>('Routine');
  className(): string { return `urgency ${this.urgency().toLowerCase()}`; }
}
