import { ChangeDetectionStrategy, Component, OnInit, computed, inject, signal } from '@angular/core';
import { LowerCasePipe } from '@angular/common';
import { FormControl, ReactiveFormsModule } from '@angular/forms';
import { MatButtonModule } from '@angular/material/button';
import { MatDialog } from '@angular/material/dialog';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatIconModule } from '@angular/material/icon';
import { MatInputModule } from '@angular/material/input';
import { MatSelectModule } from '@angular/material/select';
import { MatTabsModule } from '@angular/material/tabs';
import { MatTooltipModule } from '@angular/material/tooltip';

import { MasterDataRow } from '../../../core/models/admin.models';
import { ViewState } from '../../../core/models/api.models';
import { Permissions } from '../../../core/models/permissions';
import { AdminService } from '../../../core/services/admin.service';
import { UiService } from '../../../core/services/ui.service';
import { errorMessage } from '../../../core/utils/api-error';
import { adminShared, serverErrorText } from '../admin-shared';
import { MASTER_TYPES, MasterTypeConfig } from './master-data.config';
import { MasterDataDialog, MasterDataDialogData } from './master-data-dialog';

@Component({
  selector: 'sb-admin-master-data',
  imports: [
    ...adminShared,
    LowerCasePipe,
    ReactiveFormsModule,
    MatButtonModule,
    MatFormFieldModule,
    MatIconModule,
    MatInputModule,
    MatSelectModule,
    MatTabsModule,
    MatTooltipModule,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './admin-master-data.html',
  styleUrl: '../admin.scss',
})
export class AdminMasterData implements OnInit {
  private readonly admin = inject(AdminService);
  private readonly ui = inject(UiService);
  private readonly dialog = inject(MatDialog);

  protected readonly P = Permissions;
  protected readonly types = MASTER_TYPES;
  protected readonly index = signal(0);
  protected readonly config = computed<MasterTypeConfig>(() => this.types[this.index()]);
  protected readonly state = signal<ViewState>('loading');
  protected readonly error = signal('');
  protected readonly rows = signal<MasterDataRow[]>([]);
  protected readonly busyId = signal<number | null>(null);
  protected readonly search = new FormControl('', { nonNullable: true });
  protected readonly activeFilter = new FormControl<'all' | 'active' | 'inactive'>('all', { nonNullable: true });
  private readonly term = signal('');
  private readonly status = signal<'all' | 'active' | 'inactive'>('all');

  protected readonly filtered = computed(() => {
    const term = this.term().trim().toLowerCase();
    const status = this.status();
    return this.rows().filter((r) => {
      if (status === 'active' && !r.isActive) return false;
      if (status === 'inactive' && r.isActive) return false;
      if (!term) return true;
      return this.config().columns.some((c) => String(r[c.key] ?? '').toLowerCase().includes(term));
    });
  });

  ngOnInit(): void {
    this.search.valueChanges.subscribe((v) => this.term.set(v));
    this.activeFilter.valueChanges.subscribe((v) => this.status.set(v));
    this.load();
  }

  protected selectTab(i: number): void {
    this.index.set(i);
    this.search.setValue('');
    this.activeFilter.setValue('all');
    this.load();
  }

  protected load(): void {
    const type = this.config().type;
    this.state.set('loading');
    this.admin.getMasterData(type).subscribe({
      next: (rows) => {
        if (type !== this.config().type) return;
        this.rows.set(rows);
        this.state.set(rows.length ? 'ready' : 'empty');
      },
      error: (err) => {
        this.error.set(errorMessage(err));
        this.state.set('error');
      },
    });
  }

  protected cell(row: MasterDataRow, key: string): string {
    const v = row[key];
    return v === null || v === undefined || v === '' ? '—' : String(v);
  }

  protected open(row: MasterDataRow | null): void {
    this.dialog
      .open<MasterDataDialog, MasterDataDialogData, boolean>(MasterDataDialog, {
        data: { config: this.config(), row },
        width: '640px',
        maxWidth: '96vw',
        autoFocus: false,
        disableClose: true,
      })
      .afterClosed()
      .subscribe((changed) => {
        if (changed) this.load();
      });
  }

  protected async toggleActive(row: MasterDataRow): Promise<void> {
    const cfg = this.config();
    const activate = !row.isActive;
    const ok = await this.ui.confirm({
      title: `${activate ? 'Activate' : 'Deactivate'} ${cfg.singular}?`,
      message: activate
        ? `${row.name} will be available for selection again.`
        : `${row.name} will no longer be offered in forms, search filters or imports. Existing records keep their reference.`,
      confirmText: activate ? 'Activate' : 'Deactivate',
      danger: !activate,
    });
    if (!ok) return;
    const body: Record<string, unknown> = { id: row.id, isActive: activate };
    for (const f of cfg.fields) body[f.key] = row[f.key] ?? null;
    this.busyId.set(row.id);
    this.admin.saveMasterData(cfg.type, body).subscribe({
      next: () => {
        this.busyId.set(null);
        this.ui.success(`${row.name} ${activate ? 'activated' : 'deactivated'}.`);
        this.load();
      },
      error: (err) => {
        this.busyId.set(null);
        this.ui.error(serverErrorText(err));
      },
    });
  }
}
