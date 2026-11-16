import { ChangeDetectionStrategy, Component, input } from '@angular/core';

@Component({
  selector: 'sb-chart-view',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="chart" [style.min-height.px]="height()">
      @for (label of labels(); track $index) {
        <div class="bar-row"><span>{{ label }}</span><div class="bar-track">
          @for (dataset of datasets(); track dataset.label) {
            <i [style.width.%]="width(dataset.data.at($index) ?? 0)" [style.background]="dataset.color || '#c8102e'" [title]="dataset.label"></i>
          }
        </div></div>
      }
    </div>
  `,
  styles: [`
    .chart { display:flex; flex-direction:column; justify-content:center; gap:.65rem; padding:.5rem }
    .bar-row { display:grid; grid-template-columns:minmax(90px,130px) 1fr; align-items:center; gap:.75rem; color:#5b6b7b; font-size:.8rem }
    .bar-track { height:14px; background:#edf1f4; border-radius:99px; overflow:hidden } i { display:block; height:100%; border-radius:inherit }
  `],
})
export class ChartView {
  readonly type = input<'bar' | 'line' | 'doughnut'>('bar');
  readonly labels = input<string[]>([]);
  readonly datasets = input<{ label: string; data: number[]; color?: string }[]>([]);
  readonly height = input(220);
  width(value: number): number {
    const max = Math.max(1, ...this.datasets().flatMap((set) => set.data));
    return Math.max(0, Math.min(100, value / max * 100));
  }
}
