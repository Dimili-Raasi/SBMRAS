import { ChangeDetectionStrategy, Component, input } from '@angular/core';
import { MatIconModule } from '@angular/material/icon';
import { PageHeader } from './page-header';

@Component({
  selector: 'sb-placeholder-page',
  standalone: true,
  imports: [MatIconModule, PageHeader],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <sb-page-header [title]="title()" [subtitle]="subtitle()" [icon]="icon()" />
    <section class="placeholder"><span><mat-icon>{{ icon() || 'science' }}</mat-icon></span>
      <h2>{{ title() }} workspace</h2><p>This screen is ready for its connected SBMRAS workflow.</p>
      <small>Reported availability can change. Please reconfirm with the facility.</small>
    </section>
  `,
  styles: [`
    .placeholder { display:grid; justify-items:center; gap:.5rem; padding:3rem 1rem; text-align:center; border:1px dashed #dce3ea; border-radius:10px; background:white; color:#5b6b7b }
    .placeholder span { display:grid; place-items:center; width:3rem; height:3rem; border-radius:50%; background:#fff0f2; color:#c8102e }.placeholder mat-icon { width:28px;height:28px;font-size:28px }
    h2 { margin:.5rem 0 0; color:#14212e } p { margin:0 } small { color:#82909d }
  `],
})
export class PlaceholderPage {
  readonly title = input('SBMRAS');
  readonly subtitle = input('');
  readonly icon = input('science');
}
