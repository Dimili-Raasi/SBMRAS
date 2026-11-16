import { ChangeDetectionStrategy, Component, DestroyRef, OnInit, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { FormControl, FormGroup, ReactiveFormsModule } from '@angular/forms';
import { DatePipe } from '@angular/common';
import { MatButtonModule } from '@angular/material/button';
import { MatDialog } from '@angular/material/dialog';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatIconModule } from '@angular/material/icon';
import { MatInputModule } from '@angular/material/input';
import { MatPaginatorModule, PageEvent } from '@angular/material/paginator';
import { MatSelectModule } from '@angular/material/select';
import { MatTooltipModule } from '@angular/material/tooltip';
import { debounceTime, distinctUntilChanged } from 'rxjs';

import { AdminUser } from '../../../core/models/admin.models';
import { ViewState } from '../../../core/models/api.models';
import { Permissions } from '../../../core/models/permissions';
import { AdminService } from '../../../core/services/admin.service';
import { errorMessage } from '../../../core/utils/api-error';
import { ADMIN_ROLE_OPTIONS, adminShared } from '../admin-shared';
import { UserDialog, UserDialogData } from './user-dialog';

@Component({
  selector: 'sb-admin-users',
  imports: [
    ...adminShared,
    DatePipe,
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
  templateUrl: './admin-users.html',
  styleUrl: '../admin.scss',
})
export class AdminUsers implements OnInit {
  private readonly admin = inject(AdminService);
  private readonly dialog = inject(MatDialog);
  private readonly destroyRef = inject(DestroyRef);

  protected readonly P = Permissions;
  protected readonly roleOptions = ADMIN_ROLE_OPTIONS;
  protected readonly state = signal<ViewState>('loading');
  protected readonly error = signal<string>('');
  protected readonly users = signal<AdminUser[]>([]);
  protected readonly total = signal(0);
  protected readonly page = signal(1);
  protected readonly pageSize = signal(20);

  protected readonly filters = new FormGroup({
    search: new FormControl<string>('', { nonNullable: true }),
    roleCode: new FormControl<string>('', { nonNullable: true }),
    isActive: new FormControl<string>('', { nonNullable: true }),
  });

  ngOnInit(): void {
    this.filters.controls.search.valueChanges
      .pipe(debounceTime(350), distinctUntilChanged(), takeUntilDestroyed(this.destroyRef))
      .subscribe(() => this.reload(true));
    this.filters.controls.roleCode.valueChanges
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe(() => this.reload(true));
    this.filters.controls.isActive.valueChanges
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
      .getUsers({
        search: f.search.trim() || null,
        roleCode: f.roleCode || null,
        isActive: f.isActive === '' ? null : f.isActive === 'true',
        page: this.page(),
        pageSize: this.pageSize(),
      })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (result) => {
          this.users.set(result.items);
          this.total.set(result.totalCount);
          this.state.set(result.items.length ? 'ready' : 'empty');
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
    this.filters.reset({ search: '', roleCode: '', isActive: '' });
  }

  open(user: AdminUser | null, tab = 0): void {
    this.dialog
      .open<UserDialog, UserDialogData, boolean>(UserDialog, {
        data: { userId: user?.userId ?? null, tab },
        width: '880px',
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
}
