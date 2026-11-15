import { Directive, Input, OnDestroy, TemplateRef, ViewContainerRef, effect, inject } from '@angular/core';

import { SessionService } from '../services/session.service';

@Directive({ selector: '[sbHasPermission]', standalone: true })
export class HasPermissionDirective implements OnDestroy {
  private readonly session = inject(SessionService);
  private readonly template = inject(TemplateRef<unknown>);
  private readonly container = inject(ViewContainerRef);
  private permission = '';
  private rendered = false;
  private readonly permissionEffect = effect(() => this.update(this.session.hasPermission(this.permission)));

  @Input()
  set sbHasPermission(permission: string) {
    this.permission = permission;
    this.update(this.session.hasPermission(permission));
  }

  ngOnDestroy(): void {
    this.permissionEffect.destroy();
  }

  private update(allowed: boolean): void {
    if (allowed && !this.rendered) {
      this.container.createEmbeddedView(this.template);
      this.rendered = true;
    } else if (!allowed && this.rendered) {
      this.container.clear();
      this.rendered = false;
    }
  }
}
