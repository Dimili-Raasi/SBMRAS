import { ChangeDetectionStrategy, Component, computed, input } from '@angular/core';

@Component({
  selector: 'sb-quality-gauge',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="gauge" role="img" [attr.aria-label]="'Data quality ' + score() + ' percent'">
      <div class="track"><div class="fill" [style.width.%]="normalized()"></div></div>
      <strong>{{ score() === null || score() === undefined ? '—' : (normalized() + '%') }}</strong>
    </div>
  `,
  styles: [`
    .gauge { display:flex; align-items:center; gap:.55rem; min-width:100px }
    .track { flex:1; height:7px; background:#e9edf1; border-radius:9px; overflow:hidden }
    .fill { height:100%; background:#00897b; border-radius:inherit }
    strong { min-width:2.5rem; color:#14212e; font:700 .8rem 'IBM Plex Mono',monospace }
  `],
})
export class QualityGauge {
  readonly score = input<number | null>(null);
  readonly normalized = computed(() => Math.max(0, Math.min(100, Math.round(this.score() ?? 0))));
}
