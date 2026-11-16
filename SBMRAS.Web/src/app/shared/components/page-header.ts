import { ChangeDetectionStrategy, Component, input } from '@angular/core';
import { MatIconModule } from '@angular/material/icon';

@Component({
  selector: 'sb-page-header',
  standalone: true,
  imports: [MatIconModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <header class="page-header">
      <div class="page-header__title">
        @if (icon()) { <span class="page-header__icon"><mat-icon>{{ icon() }}</mat-icon></span> }
        <div><h1>{{ title() }}</h1>@if (subtitle()) { <p>{{ subtitle() }}</p> }</div>
      </div>
      <div class="page-header__actions"><ng-content /></div>
    </header>
  `,
  styles: [`
    :host { display:block; margin:0 0 1.25rem }
    .page-header { display:flex; align-items:center; justify-content:space-between; gap:1rem }
    .page-header__title { display:flex; align-items:center; gap:.8rem }
    .page-header__icon { display:grid; place-items:center; width:2.6rem; height:2.6rem; border-radius:10px; background:#fff0f2; color:#c8102e }
    h1 { margin:0; color:#14212e; font-size:clamp(1.35rem,2vw,1.8rem); font-weight:700 }
    p { margin:.25rem 0 0; color:#5b6b7b }
    .page-header__actions { display:flex; align-items:center; gap:.5rem }
    @media(max-width:640px) { .page-header { align-items:flex-start; flex-direction:column } }
  `],
})
export class PageHeader {
  readonly title = input.required<string>();
  readonly subtitle = input('');
  readonly icon = input('');
}
