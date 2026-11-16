import { ChangeDetectionStrategy, Component, DestroyRef, OnInit, computed, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { NavigationEnd, Router, RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { MatIconModule } from '@angular/material/icon';
import { filter } from 'rxjs';

import { MenuService } from '../core/services/menu.service';
import { NotificationBadgeService } from '../core/services/notification-badge.service';
import { SessionService } from '../core/services/session.service';
import { LoadingService } from '../core/services/loading.service';
import { AuthService } from '../core/services/auth.service';

@Component({
  selector: 'sb-app-shell',
  standalone: true,
  imports: [RouterOutlet, RouterLink, RouterLinkActive, MatIconModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <header class="top-nav">
      <a routerLink="/" class="brand" aria-label="SBMRAS home">
        <span class="brand-icon"><mat-icon>bloodtype</mat-icon></span>
        <span class="brand-copy"><strong>SBMRAS</strong><small>Blood &amp; Medical Resource Availability</small></span>
      </a>
      <button class="mobile-toggle" type="button" aria-label="Open navigation" (click)="toggleMobile()">
        <mat-icon>{{ mobileOpen() ? 'close' : 'menu' }}</mat-icon>
      </button>
      <nav class="sections" aria-label="Main sections">
        @for (section of menu.sections(); track section.section) {
          <button type="button" [class.active]="menu.activeSection() === section.section" (click)="select(section.section)">
            {{ section.section }}
          </button>
        }
      </nav>
      <div class="top-actions">
        <a class="find-button" routerLink="/find-blood"><mat-icon>search</mat-icon><span>Find blood</span></a>
        @if (session.isAuthenticated()) {
          <a class="notification" routerLink="/notifications" aria-label="Notifications">
            <mat-icon>notifications</mat-icon>@if (badge.count() > 0) { <b>{{ badge.count() > 99 ? '99+' : badge.count() }}</b> }
          </a>
          <button class="user-button" type="button" (click)="toggleUserMenu()" [attr.aria-expanded]="userMenuOpen()">
            <span class="avatar">{{ initials() }}</span><span class="user-name">{{ session.user()?.displayName }}</span><mat-icon>expand_more</mat-icon>
          </button>
        } @else {
          <a class="signin-button" routerLink="/login">Sign in / Register</a>
        }
      </div>
      @if (userMenuOpen() && session.user(); as user) {
        <div class="user-menu">
          <strong>{{ user.displayName }}</strong><small>{{ user.email }}</small>
          <div class="role-chips">@for (role of user.roleNames; track role) { <span>{{ role }}</span> }</div>
          @if (user.facilities.length) { <small class="facility-list">{{ user.facilities.length }} assigned facility{{ user.facilities.length === 1 ? '' : 'ies' }}</small> }
          <a routerLink="/profile" (click)="userMenuOpen.set(false)">My profile</a>
          <button type="button" (click)="signOut()">Sign out</button>
        </div>
      }
      @if (mobileOpen()) {
        <div class="mobile-sheet">
          @for (section of menu.sections(); track section.section) {
            <section><button class="mobile-section" type="button" (click)="select(section.section)">{{ section.section }}</button>
              @if (menu.activeSection() === section.section) {
                <div class="mobile-links">@for (item of section.items; track item.code) { <a [routerLink]="item.route" (click)="mobileOpen.set(false)"><mat-icon>{{ item.icon }}</mat-icon>{{ item.label }}</a> }</div>
              }
            </section>
          }
          @if (!session.isAuthenticated()) { <a class="mobile-login" routerLink="/login" (click)="mobileOpen.set(false)">Sign in / Register</a> }
        </div>
      }
    </header>
    <nav class="sub-nav" aria-label="Section pages">
      <div class="sub-links">
        @for (item of menu.activeItems(); track item.code) {
          <a [routerLink]="item.route" routerLinkActive="active" [routerLinkActiveOptions]="{ exact: true }">
            <mat-icon>{{ item.icon }}</mat-icon>{{ item.label }}
          </a>
        }
      </div>
      <span class="context">{{ currentContext() }}</span>
    </nav>
    @if (loading.isLoading()) { <div class="loading-line" role="progressbar"></div> }
    <main class="content"><router-outlet /></main>
    <footer class="footer">SBMRAS shows reported availability. Always reconfirm with the facility. Not a clinical decision tool.</footer>
  `,
  styles: [`
    :host { min-height:100vh; display:flex; flex-direction:column; color:#14212e }
    .top-nav { position:relative; z-index:20; min-height:64px; display:flex; align-items:center; gap:1.5rem; padding:0 clamp(1rem,3vw,2.5rem); color:#fff; background-color:#0b1f33; background-image:url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='72' height='62' viewBox='0 0 72 62'%3E%3Cpath d='M18 1 35 10v19L18 38 1 29V10zM54 31 71 40v19L54 68 37 59V40z' fill='none' stroke='%23ffffff' stroke-opacity='.055'/%3E%3Ccircle cx='18' cy='19' r='1.5' fill='%23c8102e' fill-opacity='.22'/%3E%3C/svg%3E\") }
    .brand { display:flex; align-items:center; gap:.65rem; color:#fff; text-decoration:none; flex:none }
    .brand-icon { display:grid; place-items:center; width:2.5rem; height:2.5rem; color:#fff; background:#c8102e; border-radius:50% }
    .brand-copy { display:flex; flex-direction:column; line-height:1.2 }.brand-copy strong { font-size:1.05rem; letter-spacing:.08em }.brand-copy small { color:#b6c5d2; font-size:.65rem; white-space:nowrap }
    .sections { display:flex; align-self:stretch; align-items:stretch; gap:.2rem; overflow-x:auto; flex:1 }
    .sections button { position:relative; padding:0 .7rem; border:0; color:#c3d0db; background:none; font-family:inherit; font-size:.85rem; font-weight:600; white-space:nowrap; cursor:pointer }
    .sections button:hover,.sections button.active { color:#fff }.sections button.active:after { position:absolute; bottom:0; left:.65rem; right:.65rem; height:3px; content:''; background:#c8102e; border-radius:3px 3px 0 0 }
    .top-actions { display:flex; align-items:center; gap:.8rem; flex:none }.top-actions a { text-decoration:none }
    .find-button,.signin-button { display:flex; align-items:center; gap:.35rem; padding:.55rem .8rem; border-radius:6px; color:white; background:#c8102e; font-size:.84rem; font-weight:700; white-space:nowrap }
    .notification { position:relative; display:grid; place-items:center; color:#d5e0e9 }.notification b { position:absolute; top:-7px; right:-8px; min-width:17px; padding:1px 3px; border-radius:99px; text-align:center; color:white; background:#c8102e; font-size:.65rem }
    .user-button { display:flex; align-items:center; gap:.45rem; border:0; color:white; background:none; cursor:pointer; font:inherit }.avatar { display:grid; place-items:center; width:2rem; height:2rem; border-radius:50%; color:#0b1f33; background:#e9f1f5; font-size:.8rem; font-weight:800 }.user-name { max-width:110px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; font-size:.83rem }
    .user-menu { position:absolute; top:calc(100% - 2px); right:1.2rem; width:260px; display:flex; flex-direction:column; gap:.55rem; padding:1rem; border:1px solid #dce3ea; border-radius:0 0 9px 9px; color:#14212e; background:white; box-shadow:0 12px 30px #0b1f3326 }
    .user-menu small { color:#667584 }.role-chips { display:flex; flex-wrap:wrap; gap:.3rem }.role-chips span { padding:.2rem .4rem; border-radius:99px; color:#087468; background:#e2f4f1; font-size:.68rem }.user-menu a,.user-menu button { padding:.4rem 0; border:0; color:#14212e; background:none; text-align:left; text-decoration:none; font:inherit; cursor:pointer }.user-menu button { color:#c8102e }
    .sub-nav { min-height:48px; display:flex; align-items:stretch; justify-content:space-between; gap:1rem; padding:0 clamp(1rem,3vw,2.5rem); border-bottom:1px solid #dce3ea; background:#fff }
    .sub-links { display:flex; gap:.2rem; overflow-x:auto }.sub-links a { position:relative; display:flex; align-items:center; gap:.4rem; padding:0 .7rem; color:#536271; text-decoration:none; font-size:.82rem; white-space:nowrap }.sub-links a mat-icon { width:18px; height:18px; font-size:18px }.sub-links a.active { color:#c8102e; font-weight:700 }.sub-links a.active:after { position:absolute; right:.6rem; bottom:0; left:.6rem; height:2px; content:''; background:#c8102e }
    .context { align-self:center; color:#83909c; font-size:.76rem; white-space:nowrap }.content { width:min(1440px,100%); flex:1; margin:0 auto; padding:clamp(1.2rem,3vw,2.25rem) clamp(1rem,3vw,2.5rem) 3rem }
    .footer { padding:1rem 1.5rem; color:#6f7c88; background:#fff; border-top:1px solid #dce3ea; text-align:center; font-size:.76rem }.loading-line { position:absolute; z-index:30; top:63px; left:0; right:0; height:2px; background:linear-gradient(90deg,transparent,#c8102e,transparent); animation:loading 1.4s infinite }
    @keyframes loading { from { transform:translateX(-100%) } to { transform:translateX(100%) } }
    .mobile-toggle,.mobile-sheet { display:none }
    @media(max-width:1050px) { .top-nav { gap:.8rem }.sections button { padding:0 .45rem;font-size:.78rem }.brand-copy small { display:none } }
    @media(max-width:900px) { .top-nav { min-height:60px }.sections,.top-actions { display:none }.mobile-toggle { margin-left:auto; display:grid; place-items:center; width:42px;height:42px;border:0;border-radius:6px;color:white;background:#ffffff1a }.mobile-sheet { position:absolute;top:100%;left:0;right:0;display:block;max-height:calc(100vh - 60px);overflow:auto;padding:1rem clamp(1rem,4vw,2rem) 1.5rem;color:#14212e;background:white;box-shadow:0 14px 25px #0b1f3333 }.mobile-section { width:100%;padding:.75rem 0;border:0;border-bottom:1px solid #e6eaee;background:none;text-align:left;font-weight:700;color:#0b1f33 }.mobile-links { display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:.3rem;padding:.45rem 0 .8rem }.mobile-links a { display:flex;align-items:center;gap:.45rem;padding:.55rem;color:#465768;text-decoration:none }.mobile-links mat-icon { font-size:19px;width:19px;height:19px }.mobile-login { display:inline-block;margin-top:.7rem;padding:.65rem .9rem;border-radius:6px;background:#c8102e;color:white;text-decoration:none;font-weight:700 } }
    @media(max-width:600px) { .brand-copy small { display:block }.brand-copy strong { font-size:.95rem }.brand-icon { width:2.15rem;height:2.15rem }.sub-nav { min-height:44px }.context { display:none }.sub-links a { padding:0 .55rem;font-size:.75rem } }
  `],
})
export class AppShell implements OnInit {
  readonly menu = inject(MenuService);
  readonly session = inject(SessionService);
  readonly badge = inject(NotificationBadgeService);
  readonly loading = inject(LoadingService);
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);
  private readonly destroyRef = inject(DestroyRef);

  readonly mobileOpen = signal(false);
  readonly userMenuOpen = signal(false);
  readonly currentContext = computed(() => {
    const path = this.router.url.split('?')[0];
    return this.menu.sections().flatMap((s) => s.items).find((item) => path === item.route || path.startsWith(`${item.route}/`))?.label ?? 'SBMRAS';
  });

  ngOnInit(): void {
    void this.initialize();
    this.router.events.pipe(filter((event) => event instanceof NavigationEnd), takeUntilDestroyed(this.destroyRef))
      .subscribe((event) => {
        const path = event.urlAfterRedirects;
        this.syncActiveSection(path);
      });
  }

  select(section: string): void {
    this.menu.selectSection(section);
    this.mobileOpen.set(false);
  }

  toggleMobile(): void { this.mobileOpen.update((value) => !value); }
  toggleUserMenu(): void { this.userMenuOpen.update((value) => !value); }

  initials(): string {
    return (this.session.user()?.displayName ?? 'U').split(/\s+/).slice(0, 2).map((part) => part[0] ?? '').join('').toUpperCase();
  }

  async signOut(): Promise<void> {
    this.userMenuOpen.set(false);
    await this.session.signOut();
    await this.menu.load();
  }

  private async initialize(): Promise<void> {
    await this.auth.initialize();
    if (this.auth.isAuthenticated) {
      await this.session.load();
    }
    await this.menu.load();
    this.syncActiveSection(this.router.url);
    await this.badge.refresh();
  }

  private syncActiveSection(path: string): void {
    const routePath = path.split('?')[0];
    const section = this.menu.sections().find((group) =>
      group.items.some((item) => routePath === item.route || routePath.startsWith(`${item.route}/`)),
    );
    if (section) this.menu.selectSection(section.section);
    else if (routePath === '/') this.menu.selectSection('Discover');
  }
}
