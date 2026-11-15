import { ChangeDetectionStrategy, Component, DestroyRef, OnInit, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { DatePipe, DecimalPipe } from '@angular/common';
import { FormControl, FormGroup, ReactiveFormsModule } from '@angular/forms';
import { MatButtonModule } from '@angular/material/button';
import { MatDialog } from '@angular/material/dialog';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatIconModule } from '@angular/material/icon';
import { MatInputModule } from '@angular/material/input';
import { MatPaginatorModule, PageEvent } from '@angular/material/paginator';
import { MatSelectModule } from '@angular/material/select';
import { MatTooltipModule } from '@angular/material/tooltip';
import { debounceTime, distinctUntilChanged } from 'rxjs';

import {
  AdminFacility,
  FACILITY_DECISIONS,
  FacilityDecision,
} from '../../../core/models/admin.models';
import { ViewState } from '../../../core/models/api.models';
import { Permissions } from '../../../core/models/permissions';
import { AdminService } from '../../../core/services/admin.service';
import { UiService } from '../../../core/services/ui.service';
import { errorMessage } from '../../../core/utils/api-error';
import { adminShared, serverErrorText } from '../admin-shared';
import { FacilityDialog, FacilityDialogData } from './facility-dialog';

const DECISION_META: Record<FacilityDecision, { label: string; icon: string; danger: boolean; notesRequired: boolean }> = {
  Verify: { label: 'Verify', icon: 'verified', danger: false, notesRequired: false },
  Reject: { label: 'Reject', icon: 'block', danger: true, notesRequired: true },
  Suspend: { label: 'Suspend', icon: 'pause_circle', danger: true, notesRequired: true },
  Reactivate: { label: 'Reactivate', icon: 'play_circle', danger: false, notesRequired: false },
};

@Component({
  selector: 'sb-admin-facilities',
  imports: [
    ...adminShared,
    DatePipe,
    DecimalPipe,
    ReactiveFormsModule,
    MatButtonModule,
    MatFormFieldModule,
    MatIconModule,
    MatInputModule,
    MatPaginatorModule,
    MatSelectModule,
    MatTooltipModule,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './admin-facilities.html',
  styleUrl: '../admin.scss',
})
export class AdminFacilities implements OnInit {
  private readonly admin = inject(AdminService);
  private readonly ui = inject(UiService);
  private readonly dialog = inject(MatDialog);
  private readonly destroyRef = inject(DestroyRef);

  protected readonly P = Permissions;
  protected readonly decisionMeta = DECISION_META;
  protected readonly statuses = ['Pending', 'Verified', 'Suspended', 'Rejected', 'Active', 'Inactive'];
  protected readonly state = signal<ViewState>('loading');
  protected readonly error = signal('');
  protected readonly facilities = signal<AdminFacility[]>([]);
  protected readonly total = signal(0);
  protected readonly page = signal(1);
  protected readonly pageSize = signal(20);
  protected readonly busyId = signal<number | null>(null);

  protected readonly filters = new FormGroup({
    search: new FormControl('', { nonNullable: true }),
    status: new FormControl('', { nonNullable: true }),
    facilityType: new FormControl('', { nonNullable: true }),
  });

  ngOnInit(): void {
    this.filters.controls.search.valueChanges
      .pipe(debounceTime(350), distinctUntilChanged(), takeUntilDestroyed(this.destroyRef))
      .subscribe(() => this.reload(true));
    this.filters.controls.status.valueChanges.pipe(takeUntilDestroyed(this.destroyRef)).subscribe(() => this.reload(true));
    this.filters.controls.facilityType.valueChanges
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe(() => this.reload(true));
    this.reload();
  }

  reload(resetPage = false): void {
    if (resetPage) {
      this.page.set(1);
    }
    const f = this.filters.getRawValue();
    this.state.set('loading');
    this.admin
      .getFacilities({
        search: f.search.trim() || null,
        status: f.status || null,
        facilityType: f.facilityType || null,
        page: this.page(),
        pageSize: this.pageSize(),
      })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (result) => {
          this.facilities.set(result.items ?? []);
          this.total.set(result.totalCount);
          this.state.set(result.items?.length ? 'ready' : 'empty');
        },
        error: (err) => {
          this.error.set(errorMessage(err));
          this.state.set('error');
        },
      });
  }

  onPage(event: PageEvent): void {
    this.page.set(event.pageIndex + 1);
    this.pageSize.set(event.pageSize);
    this.reload();
  }

  clearFilters(): void {
    this.filters.reset({ search: '', status: '', facilityType: '' });
  }

  decisionsFor(f: AdminFacility): FacilityDecision[] {
    return FACILITY_DECISIONS[f.verificationStatus] ?? [];
  }

  open(facility: AdminFacility | null): void {
    this.dialog
      .open<FacilityDialog, FacilityDialogData, boolean>(FacilityDialog, {
        data: { facility },
        width: '760px',
        maxWidth: '96vw',
        maxHeight: '92vh',
        autoFocus: false,
        disableClose: true,
      })
      .afterClosed()
      .subscribe((changed) => {
        if (changed) {
          this.reload();
        }
      });
  }

  async decide(f: AdminFacility, decision: FacilityDecision): Promise<void> {
    const meta = DECISION_META[decision];
    const notes = await this.ui.reason({
      title: `${meta.label} ${f.name}?`,
      label: meta.notesRequired ? 'Reason (shared with facility users)' : 'Notes (optional)',
      required: meta.notesRequired,
    });
    if (notes === null) {
      return;
    }
    this.busyId.set(f.facilityId);
    this.admin.verifyFacility(f.facilityId, decision, notes.trim() || null).subscribe({
      next: (updated) => {
        this.busyId.set(null);
        this.ui.success(`${f.name} is now ${updated?.verificationStatus ?? 'updated'}.`);
        this.reload();
      },
      error: (err) => {
        this.busyId.set(null);
        this.ui.error(serverErrorText(err));
      },
    });
  }

  statusTone(status: string): string {
    switch (status) {
      case 'Verified':
        return 'ok';
      case 'Pending':
        return 'info';
      case 'Suspended':
        return 'warn';
      default:
        return 'bad';
    }
  }
}
