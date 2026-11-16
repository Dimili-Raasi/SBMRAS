import { ChangeDetectionStrategy, Component, OnInit, inject, signal } from '@angular/core';
import { FormControl, FormGroup, ReactiveFormsModule, ValidatorFn, Validators } from '@angular/forms';
import { MatButtonModule } from '@angular/material/button';
import { MAT_DIALOG_DATA, MatDialogModule, MatDialogRef } from '@angular/material/dialog';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatIconModule } from '@angular/material/icon';
import { MatInputModule } from '@angular/material/input';
import { MatProgressBarModule } from '@angular/material/progress-bar';
import { MatSelectModule } from '@angular/material/select';
import { MatSlideToggleModule } from '@angular/material/slide-toggle';

import { MasterDataRow } from '../../../core/models/admin.models';
import { AdminService } from '../../../core/services/admin.service';
import { UiService } from '../../../core/services/ui.service';
import { errorMessage } from '../../../core/utils/api-error';
import { serverErrorText } from '../admin-shared';
import { MasterField, MasterTypeConfig } from './master-data.config';

export interface MasterDataDialogData {
  config: MasterTypeConfig;
  row: MasterDataRow | null;
}

type Option = { value: string | number; label: string };

@Component({
  selector: 'sb-master-data-dialog',
  imports: [
    ReactiveFormsModule,
    MatButtonModule,
    MatDialogModule,
    MatFormFieldModule,
    MatIconModule,
    MatInputModule,
    MatProgressBarModule,
    MatSelectModule,
    MatSlideToggleModule,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './master-data-dialog.html',
  styleUrl: '../admin.scss',
})
export class MasterDataDialog implements OnInit {
  private readonly admin = inject(AdminService);
  private readonly ui = inject(UiService);
  private readonly ref = inject<MatDialogRef<MasterDataDialog, boolean>>(MatDialogRef);
  protected readonly data = inject<MasterDataDialogData>(MAT_DIALOG_DATA);

  protected readonly config = this.data.config;
  protected readonly row = this.data.row;
  protected readonly isNew = !this.row;
  protected readonly saving = signal(false);
  protected readonly formError = signal('');
  protected readonly options = signal<Record<string, Option[]>>({});
  protected readonly form = new FormGroup<Record<string, FormControl>>({});

  ngOnInit(): void {
    for (const f of this.config.fields) {
      this.form.addControl(f.key, new FormControl(this.row?.[f.key] ?? (f.kind === 'number' ? null : ''), this.validators(f)));
      if (f.options) {
        this.options.update((o) => ({ ...o, [f.key]: f.options! }));
      } else if (f.optionsFrom) {
        this.admin.getMasterData(f.optionsFrom).subscribe({
          next: (rows) =>
            this.options.update((o) => ({
              ...o,
              [f.key]: rows
                .filter((r) => r.isActive || r.id === this.row?.[f.key])
                .map((r) => ({ value: r.id, label: r.code ? `${r.code} · ${r.name}` : r.name })),
            })),
          error: (err) => this.formError.set(`Could not load ${f.label.toLowerCase()} options: ${errorMessage(err)}`),
        });
      }
    }
    this.form.addControl('isActive', new FormControl<boolean>(this.row?.isActive ?? true, { nonNullable: true }));
  }

  private validators(f: MasterField): ValidatorFn[] {
    const v: ValidatorFn[] = [];
    if (f.required) v.push(Validators.required);
    if (f.maxLength) v.push(Validators.maxLength(f.maxLength));
    if (f.min !== undefined) v.push(Validators.min(f.min));
    if (f.max !== undefined) v.push(Validators.max(f.max));
    if (f.pattern) v.push(Validators.pattern(f.pattern));
    if (f.kind === 'number') v.push(Validators.pattern(/^-?\d+$/));
    return v;
  }

  protected ctrl(key: string): FormControl {
    return this.form.controls[key];
  }

  protected errorFor(f: MasterField): string {
    const c = this.ctrl(f.key);
    if (c.hasError('required')) return `${f.label} is required.`;
    if (c.hasError('maxlength')) return `Maximum ${f.maxLength} characters.`;
    if (c.hasError('min') || c.hasError('max')) return `Must be between ${f.min} and ${f.max}.`;
    if (c.hasError('pattern')) return f.patternHint ?? 'Enter a whole number.';
    return '';
  }

  protected async save(): Promise<void> {
    this.formError.set('');
    if (this.form.invalid) {
      this.form.markAllAsTouched();
      this.formError.set('Fix the highlighted fields and try again.');
      return;
    }
    const raw = this.form.getRawValue();
    if (!this.isNew && this.row!.isActive && raw['isActive'] === false) {
      const ok = await this.ui.confirm({
        title: `Deactivate ${this.config.singular}?`,
        message: `${raw['name']} will no longer be offered in forms, filters or imports.`,
        confirmText: 'Deactivate',
        danger: true,
      });
      if (!ok) return;
    }
    const body: Record<string, unknown> = { id: this.row?.id ?? 0, isActive: raw['isActive'] };
    for (const f of this.config.fields) {
      let value = raw[f.key];
      if (typeof value === 'string') value = value.trim();
      if (f.kind === 'code' && typeof value === 'string') value = value.toUpperCase();
      if (f.kind === 'number' && value !== null && value !== '') value = Number(value);
      body[f.key] = value === '' ? null : value;
    }
    this.saving.set(true);
    this.admin.saveMasterData(this.config.type, body).subscribe({
      next: () => {
        this.saving.set(false);
        this.ui.success(`${this.config.singular[0].toUpperCase()}${this.config.singular.slice(1)} ${this.isNew ? 'created' : 'updated'}.`);
        this.ref.close(true);
      },
      error: (err) => {
        this.saving.set(false);
        this.formError.set(serverErrorText(err));
      },
    });
  }

  protected async close(): Promise<void> {
    if (this.form.dirty) {
      const ok = await this.ui.confirm({
        title: 'Discard changes?',
        message: 'You have unsaved changes that will be lost.',
        confirmText: 'Discard',
        danger: true,
      });
      if (!ok) return;
    }
    this.ref.close(false);
  }
}
