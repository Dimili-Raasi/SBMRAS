import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { MAT_DIALOG_DATA, MatDialogModule } from '@angular/material/dialog';
import { MatButtonModule } from '@angular/material/button';

export interface ReasonDialogData { title: string; label?: string; required?: boolean }

@Component({
  selector: 'sb-reason-dialog',
  standalone: true,
  imports: [FormsModule, MatDialogModule, MatButtonModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <h2 mat-dialog-title>{{ data.title }}</h2>
    <mat-dialog-content>
      <label class="reason-label">{{ data.label || 'Reason' }}@if (data.required) { <span>*</span> }</label>
      <textarea rows="4" [(ngModel)]="value" maxlength="1000"></textarea>
    </mat-dialog-content>
    <mat-dialog-actions align="end">
      <button mat-button mat-dialog-close>Cancel</button>
      <button mat-flat-button color="primary" [disabled]="data.required && !value.trim()" [mat-dialog-close]="value.trim()">Continue</button>
    </mat-dialog-actions>
  `,
  styles: [`.reason-label { display:block; margin-bottom:.4rem; font-weight:600 } .reason-label span { color:#c8102e } textarea { width:100%; box-sizing:border-box; padding:.7rem; border:1px solid #cfd7df; border-radius:6px; font:inherit }`],
})
export class ReasonDialog {
  readonly data = inject<ReasonDialogData>(MAT_DIALOG_DATA);
  value = '';
}
