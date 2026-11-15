import { ChangeDetectionStrategy, Component, input, output } from '@angular/core';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';

@Component({
  selector: 'sb-state-panel',
  standalone: true,
  imports: [MatButtonModule, MatIconModule, MatProgressSpinnerModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <section class="state-panel" [attr.aria-live]="state() === 'loading' ? 'polite' : 'assertive'">
      @if (state() === 'loading') {
        <mat-spinner diameter="32" />
        <p>{{ message() || 'Loading…' }}</p>
      } @else if (state() === 'error') {
        <mat-icon class="error-icon">error_outline</mat-icon>
        <p>{{ message() || 'We could not load this information.' }}</p>
        <button mat-stroked-button color="primary" type="button" (click)="retry.emit()"><mat-icon>refresh</mat-icon> Try again</button>
      } @else {
        <mat-icon>inbox</mat-icon>
        <p>{{ message() || 'No information to show yet.' }}</p>
      }
    </section>
  `,
  styles: [`
    .state-panel { min-height:180px; padding:2rem; display:flex; flex-direction:column; align-items:center; justify-content:center; gap:.75rem; color:#5b6b7b; text-align:center; border:1px dashed #dce3ea; border-radius:10px; background:#fff }
    p { margin:0 } mat-icon { color:#8a96a3 } .error-icon { color:#d93025 }
  `],
})
export class StatePanel {
  readonly state = input<'loading' | 'empty' | 'error'>('empty');
  readonly message = input('');
  readonly retry = output<void>();
}
