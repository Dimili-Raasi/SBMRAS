import { computed, signal } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';

import { AuthService } from '../core/services/auth.service';
import { LoadingService } from '../core/services/loading.service';
import { MenuService } from '../core/services/menu.service';
import { NotificationBadgeService } from '../core/services/notification-badge.service';
import { SessionService } from '../core/services/session.service';
import { AppShell } from './app-shell';

describe('AppShell', () => {
  it('renders primary sections in the top navigation', async () => {
    const items = [{ code: 'search.blood', label: 'Find Blood', icon: 'bloodtype', route: '/find-blood', sortOrder: 1 }];
    const sections = signal([{ section: 'Discover', sectionOrder: 1, items }]);
    const activeSection = signal('Discover');
    const menu = {
      sections: sections.asReadonly(),
      activeSection,
      activeItems: computed(() => sections().find((section) => section.section === activeSection())?.items ?? []),
      selectSection: (section: string) => activeSection.set(section),
      load: async () => undefined,
    };

    await TestBed.configureTestingModule({
      imports: [AppShell],
      providers: [
        provideRouter([]),
        { provide: MenuService, useValue: menu },
        { provide: SessionService, useValue: { isAuthenticated: signal(false), user: signal(null) } },
        { provide: NotificationBadgeService, useValue: { count: signal(0), refresh: async () => undefined } },
        { provide: LoadingService, useValue: { isLoading: signal(false) } },
        { provide: AuthService, useValue: { initialize: async () => undefined, isAuthenticated: false } },
      ],
    }).compileComponents();

    const fixture = TestBed.createComponent(AppShell);
    fixture.detectChanges();
    await fixture.whenStable();
    fixture.detectChanges();

    const primaryNavigation = fixture.nativeElement.querySelector('header.top-nav nav[aria-label="Main sections"]');
    expect(primaryNavigation).not.toBeNull();
    expect(primaryNavigation.textContent).toContain('Discover');
    expect(fixture.nativeElement.querySelector('aside')).toBeNull();
  });
});
