import { ChangeDetectionStrategy, Component, input } from '@angular/core';
import { DatePipe } from '@angular/common';
import { MatIconModule } from '@angular/material/icon';

@Component({
  selector: 'sb-freshness-badge',
  standalone: true,
  imports: [DatePipe, MatIconModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <span class="freshness" [class]="className()">
      <mat-icon>{{ icon() }}</mat-icon>{{ status() || 'Unknown' }}
      @if (lastUpdatedAt()) { <small> · {{ lastUpdatedAt() | date:'short' }}</small> }
    </span>
  `,
  styles: [`
    .freshness { display:inline-flex; align-items:center; gap:.2rem; font-size:.75rem; font-weight:700; color:#687582 }
    mat-icon { width:16px; height:16px; font-size:16px } .fresh { color:#2e9e5b } .aging { color:#9a6a00 }
    .stale { color:#d93025 } .under-review { color:#7b4fd6 }
  `],
})
export class FreshnessBadge {
  readonly status = input<string | null>('Unknown');
  readonly lastUpdatedAt = input<string | Date | null>(null);
  readonly validUntil = input<string | Date | null>(null);

  className(): string { return `freshness ${String(this.status() ?? 'Unknown').toLowerCase().replace(/\s/g, '-')}`; }
  icon(): string {
    return ({ Fresh: 'check_circle', Aging: 'schedule', Stale: 'error', UnderReview: 'pending', Unknown: 'help' } as Record<string, string>)[this.status() ?? 'Unknown'] ?? 'help';
  }
}
