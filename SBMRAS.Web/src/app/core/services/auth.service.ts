import { Injectable, inject } from '@angular/core';
import { PublicClientApplication, AccountInfo, AuthenticationResult } from '@azure/msal-browser';
import { firstValueFrom } from 'rxjs';

import { environment } from '../../../environments/environment';
import { AuthConfig, DevUser } from '../models/auth.models';
import { ApiService } from './api.service';

@Injectable({ providedIn: 'root' })
export class AuthService {
  private readonly api = inject(ApiService);
  private config: AuthConfig = { mode: environment.auth.mode };
  private msal: PublicClientApplication | null = null;
  private ready: Promise<void> | null = null;
  private activeAccount: AccountInfo | null = null;
  private devUserId: number | null = this.readDevUserId();

  async initialize(): Promise<void> {
    if (this.ready) return this.ready;
    this.ready = (async () => {
      try {
        const runtimeConfig = await firstValueFrom(this.api.get<AuthConfig>('auth/config'));
        if (runtimeConfig?.mode) this.config = runtimeConfig;
      } catch {
        this.config = { ...this.config, mode: environment.auth.mode };
      }
      if (this.config.mode === 'EntraId') {
        const authorityBase = this.config.authority || environment.auth.authority;
        const userFlow = this.config.userFlow || environment.auth.userFlow;
        // B2C puts the user flow in the authority path; External ID (ciamlogin.com) links the flow to the app instead.
        const isB2c = /\.b2clogin\.com/i.test(authorityBase);
        const authority = isB2c && userFlow && !authorityBase.toLowerCase().endsWith(userFlow.toLowerCase())
          ? `${authorityBase.replace(/\/$/, '')}/${userFlow}`
          : authorityBase;
        this.msal = new PublicClientApplication({
          auth: {
            clientId: this.config.spaClientId || environment.auth.clientId,
            authority,
            knownAuthorities: this.config.knownAuthority
              ? [this.config.knownAuthority]
              : environment.auth.knownAuthorities,
            redirectUri: window.location.origin,
            postLogoutRedirectUri: window.location.origin,
          },
          cache: { cacheLocation: 'sessionStorage' },
        });
        await this.msal.initialize();
        const result = await this.msal.handleRedirectPromise();
        this.activeAccount = result?.account ?? this.msal.getActiveAccount() ?? this.msal.getAllAccounts()[0] ?? null;
        if (this.activeAccount) this.msal.setActiveAccount(this.activeAccount);
      }
    })();
    return this.ready;
  }

  get mode(): 'DevHeader' | 'EntraId' {
    return this.config.mode;
  }

  get isAuthenticated(): boolean {
    return this.mode === 'DevHeader' ? this.devUserId !== null : this.activeAccount !== null;
  }

  async devUsers(): Promise<DevUser[]> {
    await this.initialize();
    return firstValueFrom(this.api.get<DevUser[]>('auth/dev-users'));
  }

  async signIn(userId?: number): Promise<void> {
    await this.initialize();
    if (this.mode === 'DevHeader') {
      if (userId === undefined) return;
      this.devUserId = userId;
      localStorage.setItem('sbmras.devUserId', String(userId));
      return;
    }
    if (!this.msal) return;
    await this.msal.loginRedirect({ scopes: this.scopes() });
  }

  async signOut(): Promise<void> {
    await this.initialize();
    this.devUserId = null;
    localStorage.removeItem('sbmras.devUserId');
    if (this.msal && this.activeAccount) {
      const account = this.activeAccount;
      this.activeAccount = null;
      await this.msal.logoutRedirect({ account });
    }
  }

  async authorizationHeaders(): Promise<Record<string, string>> {
    await this.initialize();
    if (this.mode === 'DevHeader') {
      return this.devUserId === null ? {} : { 'X-User-Id': String(this.devUserId) };
    }
    const token = await this.acquireToken();
    return token ? { Authorization: `Bearer ${token}` } : {};
  }

  private async acquireToken(): Promise<string | null> {
    if (!this.msal || !this.activeAccount) return null;
    try {
      const result: AuthenticationResult = await this.msal.acquireTokenSilent({
        account: this.activeAccount,
        scopes: this.scopes(),
      });
      return result.accessToken;
    } catch {
      await this.msal.acquireTokenRedirect({ scopes: this.scopes(), account: this.activeAccount });
      return null;
    }
  }

  private scopes(): string[] {
    const scope = this.config.apiScope || environment.auth.apiScope;
    return scope ? [scope] : [];
  }

  private readDevUserId(): number | null {
    if (typeof localStorage === 'undefined') return null;
    const value = Number(localStorage.getItem('sbmras.devUserId'));
    return Number.isInteger(value) && value > 0 ? value : null;
  }
}
