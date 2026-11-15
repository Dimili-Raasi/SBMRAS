import { ChangeDetectionStrategy, Component, OnInit, inject, signal } from '@angular/core';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { MatButtonModule } from '@angular/material/button';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatIconModule } from '@angular/material/icon';
import { MatSelectModule } from '@angular/material/select';

import { DevUser } from '../../core/models/auth.models';
import { AuthService } from '../../core/services/auth.service';
import { SessionService } from '../../core/services/session.service';
import { MenuService } from '../../core/services/menu.service';

@Component({
  selector: 'sb-login',
  standalone: true,
  imports: [RouterLink, MatButtonModule, MatFormFieldModule, MatIconModule, MatSelectModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <main class="login-page">
      <section class="login-art">
        <a routerLink="/" class="brand"><span>✚</span> SBMRAS</a>
        <div><p class="eyebrow">Connected care starts here</p><h1>Better visibility.<br>Stronger response.</h1>
          <p>Coordinate blood and essential medical resources across trusted facilities.</p></div>
        <small>Availability is reported by facilities. Always reconfirm directly.</small>
      </section>
      <section class="login-form">
        <div class="form-card">
          <span class="overline">SECURE ACCESS</span><h2>Welcome back</h2><p>Sign in to your SBMRAS workspace.</p>
          @if (mode() === 'DevHeader') {
            @if (error()) { <div class="error">{{ error() }}</div> }
            <mat-form-field appearance="outline"><mat-label>Development user</mat-label>
              <mat-select [value]="selectedUser()" (valueChange)="selectedUser.set($event)">
                @for (user of users(); track user.userId) { <mat-option [value]="user.userId">{{ user.displayName }} · {{ user.roleName }}</mat-option> }
              </mat-select>
            </mat-form-field>
            <button mat-flat-button color="primary" class="signin" [disabled]="!selectedUser() || busy()" (click)="signIn()">
              <mat-icon>login</mat-icon> Sign in locally
            </button>
            @if (!users().length && !error()) { <p class="muted">Loading development users…</p> }
          } @else {
            <button mat-flat-button color="primary" class="signin" [disabled]="busy()" (click)="signIn()">
              <mat-icon>lock</mat-icon> Sign in with Microsoft
            </button>
            <p class="muted">You will be redirected to your organization’s secure sign-in.</p>
          }
          <a class="back" routerLink="/">← Back to public information</a>
        </div>
      </section>
    </main>
  `,
  styles: [`
    .login-page { min-height:100vh; display:grid; grid-template-columns:1fr 1fr; background:#fff }
    .login-art { padding:clamp(2rem,7vw,7rem); display:flex; flex-direction:column; justify-content:space-between; color:white; background:radial-gradient(circle at 75% 20%,#284b64,transparent 36%),linear-gradient(135deg,#0b1f33,#102d43) }
    .brand { display:flex; align-items:center; gap:.6rem; color:white; text-decoration:none; font-size:1.2rem; font-weight:800; letter-spacing:.08em }.brand span { display:grid; place-items:center; width:2.2rem; height:2.2rem; border-radius:50%; color:white; background:#c8102e }
    h1 { margin:.5rem 0 1rem; font-size:clamp(2.4rem,5vw,4.2rem); line-height:1.05 }.login-art p:not(.eyebrow) { max-width:32rem; color:#d5e0e9; font-size:1.1rem; line-height:1.7 }.eyebrow,.overline { color:#e7a4af; font:700 .75rem 'IBM Plex Mono',monospace; letter-spacing:.13em }
    .login-art small { color:#b6c5d2 }.login-form { display:grid; place-items:center; padding:2rem }.form-card { width:min(420px,100%); display:flex; flex-direction:column; gap:1rem }.form-card h2 { margin:0; color:#14212e; font-size:2rem }.form-card p { margin:0; color:#657484 }.signin { min-height:48px }.muted { font-size:.85rem }.error { padding:.75rem; border-radius:6px; color:#a50c25; background:#fff0f2 }.back { color:#5b6b7b; text-decoration:none; font-size:.9rem; margin-top:.5rem }
    @media(max-width:760px) { .login-page { grid-template-columns:1fr }.login-art { min-height:260px; gap:2rem }.login-art h1 { font-size:2.4rem }.login-art small { display:none }.login-form { padding:2rem 1.3rem } }
  `],
})
export class Login implements OnInit {
  private readonly auth = inject(AuthService);
  private readonly session = inject(SessionService);
  private readonly menu = inject(MenuService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);

  readonly mode = signal<'DevHeader' | 'EntraId'>('DevHeader');
  readonly users = signal<DevUser[]>([]);
  readonly selectedUser = signal<number | null>(null);
  readonly error = signal('');
  readonly busy = signal(false);

  async ngOnInit(): Promise<void> {
    await this.auth.initialize();
    this.mode.set(this.auth.mode);
    if (this.auth.mode === 'DevHeader') {
      try {
        this.users.set(await this.auth.devUsers());
        this.selectedUser.set(this.users()[0]?.userId ?? null);
      } catch {
        this.error.set('Development sign-in is unavailable. Confirm the local API is running.');
      }
    }
  }

  async signIn(): Promise<void> {
    this.busy.set(true);
    this.error.set('');
    try {
      await this.auth.signIn(this.selectedUser() ?? undefined);
      if (this.auth.mode === 'DevHeader') {
        const user = await this.session.load(true);
        if (!user) throw new Error('Could not load your profile. Please try again.');
        await this.menu.load();
        const returnUrl = this.route.snapshot.queryParamMap.get('returnUrl');
        await this.router.navigateByUrl(returnUrl?.startsWith('/') && !returnUrl.startsWith('//') ? returnUrl : '/dashboard');
      }
    } catch (error) {
      this.error.set(error instanceof Error ? error.message : 'Sign-in failed.');
    } finally {
      this.busy.set(false);
    }
  }
}
