import { Injectable, computed, inject, signal } from '@angular/core';
import { Router } from '@angular/router';
import { firstValueFrom } from 'rxjs';

import { CurrentUser, UserFacility } from '../models/auth.models';
import { ApiService } from './api.service';
import { AuthService } from './auth.service';

@Injectable({ providedIn: 'root' })
export class SessionService {
  private readonly api = inject(ApiService);
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);

  private readonly currentUser = signal<CurrentUser | null>(null);
  readonly user = this.currentUser.asReadonly();
  readonly isAuthenticated = computed(() => this.currentUser() !== null);
  readonly permissions = computed(() => this.currentUser()?.permissions ?? []);
  readonly facilities = computed<UserFacility[]>(() => this.currentUser()?.facilities ?? []);
  private loading: Promise<CurrentUser | null> | null = null;

  hasPermission(code: string): boolean {
    return this.permissions().includes(code);
  }

  hasAnyPermission(codes: string[]): boolean {
    return codes.some((code) => this.hasPermission(code));
  }

  async load(force = false): Promise<CurrentUser | null> {
    if (!force && this.currentUser()) return this.currentUser();
    if (this.loading) return this.loading;
    this.loading = this.fetchUser().finally(() => {
      this.loading = null;
    });
    return this.loading;
  }

  private async fetchUser(): Promise<CurrentUser | null> {
    // Guards run in parallel; MSAL must finish handling the redirect before the account is known.
    await this.auth.initialize();
    if (!this.auth.isAuthenticated) {
      this.currentUser.set(null);
      return null;
    }
    try {
      const user = await firstValueFrom(this.api.get<CurrentUser>('me'));
      this.currentUser.set(user);
      return user;
    } catch {
      this.currentUser.set(null);
      return null;
    }
  }

  setUser(user: CurrentUser | null): void {
    this.currentUser.set(user);
  }

  async signOut(): Promise<void> {
    this.currentUser.set(null);
    await this.auth.signOut();
    await this.router.navigateByUrl('/');
  }
}
