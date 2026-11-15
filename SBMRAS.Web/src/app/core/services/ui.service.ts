import { Injectable, inject } from '@angular/core';
import { MatDialog } from '@angular/material/dialog';
import { MatSnackBar } from '@angular/material/snack-bar';
import { firstValueFrom, map } from 'rxjs';

import { ConfirmDialog, ConfirmDialogData } from '../../shared/components/confirm-dialog';
import { ReasonDialog, ReasonDialogData } from '../../shared/components/reason-dialog';

@Injectable({ providedIn: 'root' })
export class UiService {
  private readonly snack = inject(MatSnackBar);
  private readonly dialog = inject(MatDialog);

  success(message: string): void {
    this.snack.open(message, 'Dismiss', { duration: 3500, panelClass: ['sb-snackbar-success'] });
  }

  error(message: string): void {
    this.snack.open(message, 'Dismiss', { duration: 6000, panelClass: ['sb-snackbar-error'] });
  }

  async confirm(data: ConfirmDialogData): Promise<boolean> {
    return firstValueFrom(this.dialog.open(ConfirmDialog, { data, width: 'min(440px, 92vw)' })
      .afterClosed().pipe(map((value) => value === true)));
  }

  async reason(data: ReasonDialogData): Promise<string | null> {
    return firstValueFrom(this.dialog.open(ReasonDialog, { data, width: 'min(480px, 92vw)' })
      .afterClosed().pipe(map((value) => typeof value === 'string' ? value : null)));
  }
}
