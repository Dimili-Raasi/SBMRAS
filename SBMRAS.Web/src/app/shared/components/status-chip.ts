import { ChangeDetectionStrategy, Component, input } from '@angular/core';

@Component({
  selector: 'sb-status-chip',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<span class="status-chip" [class]="className()">{{ label() }}</span>`,
  styles: [`
    .status-chip { display:inline-flex; align-items:center; padding:.2rem .55rem; border-radius:999px; background:#edf1f4; color:#566575; font-size:.75rem; font-weight:700; white-space:nowrap }
    .blue { background:#e7f0ff; color:#1e5ab4 } .purple { background:#f0eafe; color:#6941a5 }
    .teal { background:#e2f4f1; color:#00796b } .amber { background:#fff4d8; color:#856000 }
    .green { background:#e7f5eb; color:#24783f } .red { background:#ffebed; color:#b32035 }
  `],
})
export class StatusChip {
  readonly status = input.required<string>();
  readonly label = input('');
  className(): string {
    const color: Record<string, string> = {
      Submitted: 'blue', UnderReview: 'purple', Matched: 'teal', Contacted: 'amber', Fulfilled: 'green',
      UnableToFulfil: 'red', Fresh: 'green', Aging: 'amber', Stale: 'red', Verified: 'green',
    };
    return `status-chip ${color[this.status()] ?? ''}`;
  }
}
