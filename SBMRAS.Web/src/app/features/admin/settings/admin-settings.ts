import { ChangeDetectionStrategy, Component, OnInit, computed, inject, signal } from '@angular/core';
import { DatePipe } from '@angular/common';
import { FormControl, FormGroup, ReactiveFormsModule, ValidatorFn, Validators } from '@angular/forms';
import { MatButtonModule } from '@angular/material/button';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatIconModule } from '@angular/material/icon';
import { MatInputModule } from '@angular/material/input';
import { MatProgressBarModule } from '@angular/material/progress-bar';
import { MatSlideToggleModule } from '@angular/material/slide-toggle';
import { MatTooltipModule } from '@angular/material/tooltip';

import { SettingUpdate, SystemSetting } from '../../../core/models/admin.models';
import { ViewState } from '../../../core/models/api.models';
import { Permissions } from '../../../core/models/permissions';
import { AdminService } from '../../../core/services/admin.service';
import { UiService } from '../../../core/services/ui.service';
import { errorMessage } from '../../../core/utils/api-error';
import { adminShared, serverErrorText } from '../admin-shared';

interface SettingMeta {
  label: string;
  suffix?: string;
  min?: number;
  max?: number;
}

/** Friendly labels and the server-side ranges enforced by usp_Settings_Update. */
const SETTING_META: Record<string, SettingMeta> = {
  BLOOD_STOCK_TTL_MINUTES: { label: 'Blood stock validity (TTL)', suffix: 'min', min: 5, max: 10080 },
  RESOURCE_TTL_MINUTES: { label: 'Medical resource validity (TTL)', suffix: 'min', min: 5, max: 10080 },
  AGING_THRESHOLD_PERCENT: { label: 'Aging threshold', suffix: '% of TTL', min: 1, max: 99 },
  LOW_STOCK_THRESHOLD_UNITS: { label: 'Low stock threshold', suffix: 'units', min: 0 },
  LARGE_JUMP_PERCENT: { label: 'Large jump — percent change', suffix: '%', min: 1, max: 1000 },
  LARGE_JUMP_MIN_UNITS: { label: 'Large jump — minimum units', suffix: 'units', min: 0 },
  REQUIRE_REVIEW_FOR_ANOMALY: { label: 'Hold anomalous updates for review' },
  MAX_IMPORT_ROWS: { label: 'Maximum rows per import', suffix: 'rows', min: 1, max: 5000 },
  EXPIRING_WITHIN_DAYS: { label: 'Expiring-soon window', suffix: 'days', min: 0 },
  QUALITY_WEIGHT_COMPLETENESS: { label: 'Completeness weight', suffix: '%', min: 0, max: 100 },
  QUALITY_WEIGHT_RECENCY: { label: 'Recency weight', suffix: '%', min: 0, max: 100 },
  QUALITY_WEIGHT_VERIFICATION: { label: 'Verification weight', suffix: '%', min: 0, max: 100 },
  QUALITY_WEIGHT_ANOMALY: { label: 'Anomaly weight', suffix: '%', min: 0, max: 100 },
  PUBLIC_SHOW_STALE_DEFAULT: { label: 'Show stale records in public search by default' },
};

const QUALITY_KEYS = Object.keys(SETTING_META).filter((k) => k.startsWith('QUALITY_WEIGHT_'));

interface SettingGroup {
  category: string;
  settings: SystemSetting[];
}

@Component({
  selector: 'sb-admin-settings',
  imports: [
    ...adminShared,
    DatePipe,
    ReactiveFormsModule,
    MatButtonModule,
    MatFormFieldModule,
    MatIconModule,
    MatInputModule,
    MatProgressBarModule,
    MatSlideToggleModule,
    MatTooltipModule,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './admin-settings.html',
  styleUrl: '../admin.scss',
})
export class AdminSettings implements OnInit {
  private readonly admin = inject(AdminService);
  private readonly ui = inject(UiService);

  protected readonly P = Permissions;
  protected readonly state = signal<ViewState>('loading');
  protected readonly error = signal('');
  protected readonly saveError = signal('');
  protected readonly saving = signal(false);
  protected readonly settings = signal<SystemSetting[]>([]);
  protected readonly form = signal(new FormGroup<Record<string, FormControl>>({}));
  private readonly values = signal<Record<string, unknown>>({});

  protected readonly groups = computed<SettingGroup[]>(() => {
    const map = new Map<string, SystemSetting[]>();
    for (const s of this.settings()) {
      const key = s.category || 'General';
      map.set(key, [...(map.get(key) ?? []), s]);
    }
    return [...map.entries()].map(([category, settings]) => ({ category, settings }));
  });

  protected readonly qualityTotal = computed(() => {
    const v = this.values();
    const present = QUALITY_KEYS.filter((k) => k in v);
    return present.length ? present.reduce((sum, k) => sum + (Number(v[k]) || 0), 0) : null;
  });

  protected readonly changes = computed<SettingUpdate[]>(() => {
    const v = this.values();
    return this.settings()
      .map((s) => ({ settingKey: s.settingKey, settingValue: this.serialize(s, v[s.settingKey]) }))
      .filter((c, i) => c.settingValue !== this.normalized(this.settings()[i]));
  });

  ngOnInit(): void {
    this.load();
  }

  protected load(): void {
    this.state.set('loading');
    this.saveError.set('');
    this.admin.getSettings().subscribe({
      next: (settings) => {
        this.apply(settings);
        this.state.set(settings.length ? 'ready' : 'empty');
      },
      error: (err) => {
        this.error.set(errorMessage(err));
        this.state.set('error');
      },
    });
  }

  private apply(settings: SystemSetting[]): void {
    const group = new FormGroup<Record<string, FormControl>>({});
    for (const s of settings) {
      const initial =
        s.dataType === 'bool'
          ? this.normalized(s) === 'true'
          : s.dataType === 'int' || s.dataType === 'decimal'
            ? Number(s.settingValue)
            : s.settingValue;
      group.addControl(s.settingKey, new FormControl(initial, this.validators(s)));
    }
    group.valueChanges.subscribe(() => this.values.set(group.getRawValue()));
    this.settings.set(settings);
    this.form.set(group);
    this.values.set(group.getRawValue());
  }

  private validators(s: SystemSetting): ValidatorFn[] {
    if (s.dataType === 'bool') return [];
    const v: ValidatorFn[] = [Validators.required];
    const meta = SETTING_META[s.settingKey];
    if (s.dataType === 'int' || s.dataType === 'decimal') {
      v.push(Validators.min(meta?.min ?? 0));
      if (meta?.max !== undefined) v.push(Validators.max(meta.max));
      if (s.dataType === 'int') v.push(Validators.pattern(/^-?\d+$/));
    } else {
      v.push(Validators.maxLength(400));
    }
    return v;
  }

  private normalized(s: SystemSetting): string {
    if (s.dataType === 'bool') return ['true', '1'].includes(String(s.settingValue).toLowerCase()) ? 'true' : 'false';
    if (s.dataType === 'int' || s.dataType === 'decimal') return String(Number(s.settingValue));
    return s.settingValue ?? '';
  }

  private serialize(s: SystemSetting, value: unknown): string {
    if (s.dataType === 'bool') return value ? 'true' : 'false';
    if (s.dataType === 'int' || s.dataType === 'decimal') return value === null || value === '' ? '' : String(Number(value));
    return String(value ?? '').trim();
  }

  protected meta(s: SystemSetting): SettingMeta {
    return SETTING_META[s.settingKey] ?? { label: this.humanize(s.settingKey) };
  }

  private humanize(key: string): string {
    const text = key.toLowerCase().replace(/_/g, ' ');
    return text.charAt(0).toUpperCase() + text.slice(1);
  }

  protected ctrl(key: string): FormControl {
    return this.form().controls[key];
  }

  protected isChanged(s: SystemSetting): boolean {
    return this.changes().some((c) => c.settingKey === s.settingKey);
  }

  protected errorFor(s: SystemSetting): string {
    const c = this.ctrl(s.settingKey);
    const m = this.meta(s);
    if (c.hasError('required')) return 'A value is required.';
    if (c.hasError('pattern')) return 'Enter a whole number.';
    if (c.hasError('min') || c.hasError('max')) {
      return m.max !== undefined ? `Allowed range ${m.min ?? 0}–${m.max}.` : `Must be at least ${m.min ?? 0}.`;
    }
    if (c.hasError('maxlength')) return 'Maximum 400 characters.';
    return '';
  }

  protected discard(): void {
    this.apply(this.settings());
    this.saveError.set('');
  }

  protected async save(): Promise<void> {
    this.saveError.set('');
    const form = this.form();
    if (form.invalid) {
      form.markAllAsTouched();
      this.saveError.set('Fix the highlighted settings and try again.');
      return;
    }
    const changes = this.changes();
    if (!changes.length) return;
    const total = this.qualityTotal();
    const weightsNote = total !== null && total !== 100 ? ` Quality weights add up to ${total}%, not 100%.` : '';
    const ok = await this.ui.confirm({
      title: 'Save system settings?',
      message: `${changes.length} setting(s) will change: ${changes.map((c) => c.settingKey).join(', ')}. Changes apply immediately to freshness, anomaly detection and quality scoring.${weightsNote}`,
      confirmText: 'Save settings',
      danger: !!weightsNote,
    });
    if (!ok) return;
    this.saving.set(true);
    this.admin.updateSettings(changes).subscribe({
      next: (settings) => {
        this.saving.set(false);
        this.ui.success('System settings saved.');
        if (Array.isArray(settings) && settings.length) {
          this.apply(settings);
        } else {
          this.load();
        }
      },
      error: (err) => {
        this.saving.set(false);
        this.saveError.set(serverErrorText(err));
      },
    });
  }
}
