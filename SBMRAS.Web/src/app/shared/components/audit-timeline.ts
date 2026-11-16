import { ChangeDetectionStrategy, Component, OnInit, inject, input, signal } from '@angular/core';
import { DatePipe } from '@angular/common';
import { ApiService } from '../../core/services/api.service';

interface TimelineEvent { action: string; description: string; userName: string | null; createdAt: string }

@Component({
  selector: 'sb-audit-timeline',
  standalone: true,
  imports: [DatePipe],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <ol class="timeline">
      @for (event of events(); track $index) {
        <li><span class="dot"></span><div><strong>{{ event.action }}</strong><p>{{ event.description }}</p><small>{{ event.userName || 'System' }} · {{ event.createdAt | date:'medium' }}</small></div></li>
      } @empty { <li class="empty">No audit activity found.</li> }
    </ol>
  `,
  styles: [`
    .timeline { margin:0; padding:0; list-style:none } li { display:flex; gap:.75rem; padding:.5rem 0 }
    .dot { width:9px; height:9px; margin:.35rem 0 0 .1rem; flex:none; border:2px solid #c8102e; border-radius:50% }
    strong { color:#14212e } p { margin:.2rem 0; color:#4f5f6e } small,.empty { color:#75818d }
  `],
})
export class AuditTimeline implements OnInit {
  readonly entityType = input.required<string>();
  readonly entityId = input.required<string | number>();
  private readonly api = inject(ApiService);
  readonly events = signal<TimelineEvent[]>([]);
  ngOnInit(): void {
    this.api.get<TimelineEvent[]>(`audit-logs/${encodeURIComponent(this.entityType())}/${encodeURIComponent(this.entityId())}`)
      .subscribe({ next: (events) => this.events.set(events ?? []), error: () => this.events.set([]) });
  }
}
