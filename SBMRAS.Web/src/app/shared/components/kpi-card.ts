import { ChangeDetectionStrategy, Component, input } from '@angular/core';
import { RouterLink } from '@angular/router';
import { MatIconModule } from '@angular/material/icon';

@Component({
  selector: 'sb-kpi-card',
  standalone: true,
  imports: [RouterLink, MatIconModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <a class="kpi" [routerLink]="route() || null">
      <span class="icon"><mat-icon>{{ icon() }}</mat-icon></span>
      <span class="body"><small>{{ label() }}</small><strong>{{ value() ?? 'Not reported' }}</strong>@if (hint()) { <em>{{ hint() }}</em> }</span>
    </a>
  `,
  styles: [`
    .kpi { display:flex; align-items:flex-start; gap:.85rem; min-height:100px; padding:1rem; color:inherit; text-decoration:none; border:1px solid #dce3ea; border-radius:10px; background:white; box-shadow:0 3px 14px #0b1f3309 }
    .icon { display:grid; place-items:center; width:2.5rem; height:2.5rem; border-radius:9px; color:#c8102e; background:#fff0f2 }
    .body { display:flex; flex-direction:column; gap:.3rem } small { color:#5b6b7b } strong { color:#14212e; font:700 1.45rem 'IBM Plex Mono',monospace } em { color:#5b6b7b; font-size:.78rem; font-style:normal }
  `],
})
export class KpiCard {
  readonly label = input.required<string>();
  readonly value = input<string | number | null>(null);
  readonly icon = input('analytics');
  readonly tone = input('primary');
  readonly hint = input('');
  readonly route = input<string | null>(null);
}
