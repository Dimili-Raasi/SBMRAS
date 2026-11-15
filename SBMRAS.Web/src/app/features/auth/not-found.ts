import { ChangeDetectionStrategy, Component } from '@angular/core';
import { RouterLink } from '@angular/router';
import { MatButtonModule } from '@angular/material/button';

@Component({
  selector: 'sb-not-found',
  standalone: true,
  imports: [RouterLink, MatButtonModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<section class="notice"><div>404</div><h1>Page not found</h1><p>The page may have moved, or the address may be incorrect.</p><a mat-flat-button color="primary" routerLink="/">Go to SBMRAS home</a></section>`,
  styles: [`.notice { min-height:55vh; display:flex; flex-direction:column; align-items:center; justify-content:center; text-align:center }.notice div { color:#c8102e; font:800 4rem 'IBM Plex Mono',monospace }h1 { margin:.5rem 0;color:#14212e }p { color:#5b6b7b }`],
})
export class NotFound {}
