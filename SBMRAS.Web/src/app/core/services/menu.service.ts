import { Injectable, computed, inject, signal } from '@angular/core';
import { firstValueFrom } from 'rxjs';

import { MenuSection } from '../models/auth.models';
import { ApiService } from './api.service';
import { SessionService } from './session.service';

const DISCOVER_MENU: MenuSection[] = [{
  section: 'Discover',
  sectionOrder: 2,
  items: [
    { code: 'search.blood', label: 'Find Blood', icon: 'bloodtype', route: '/find-blood', sortOrder: 1 },
    { code: 'search.resources', label: 'Medical Resources', icon: 'medical_services', route: '/find-resources', sortOrder: 2 },
    { code: 'search.facilities', label: 'Facility Directory', icon: 'local_hospital', route: '/directory', sortOrder: 3 },
  ],
}];

@Injectable({ providedIn: 'root' })
export class MenuService {
  private readonly api = inject(ApiService);
  private readonly session = inject(SessionService);
  private readonly sectionsState = signal<MenuSection[]>(DISCOVER_MENU);
  readonly sections = this.sectionsState.asReadonly();
  readonly activeSection = signal('Discover');
  readonly activeItems = computed(() => this.sectionsState().find((s) => s.section === this.activeSection())?.items ?? []);

  async load(): Promise<void> {
    if (!this.session.isAuthenticated()) {
      this.sectionsState.set(DISCOVER_MENU);
      this.activeSection.set('Discover');
      return;
    }
    try {
      const sections = await firstValueFrom(this.api.get<MenuSection[]>('me/menu'));
      this.sectionsState.set(sections?.length ? sections : DISCOVER_MENU);
    } catch {
      this.sectionsState.set(DISCOVER_MENU);
    }
    if (!this.sectionsState().some((s) => s.section === this.activeSection())) {
      this.activeSection.set(this.sectionsState()[0]?.section ?? 'Discover');
    }
  }

  selectSection(section: string): void {
    this.activeSection.set(section);
  }
}
