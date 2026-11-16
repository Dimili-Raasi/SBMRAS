import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import { MatButtonModule } from '@angular/material/button';
import { PageHeader } from '../../shared/components/page-header';
import { SessionService } from '../../core/services/session.service';

@Component({
  selector: 'sb-profile',
  standalone: true,
  imports: [RouterLink, MatButtonModule, PageHeader],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <sb-page-header title="My profile" subtitle="Your SBMRAS account and assigned facilities" icon="account_circle" />
    @if (session.user(); as user) {
      <section class="profile-card">
        <div class="avatar">{{ initials(user.displayName) }}</div><div><h2>{{ user.displayName }}</h2><p>{{ user.email || 'No email address on file' }}</p></div>
        <dl><dt>Primary role</dt><dd>{{ user.primaryRole }}</dd><dt>Organization</dt><dd>{{ user.organizationName || 'Not assigned' }}</dd><dt>Area</dt><dd>{{ user.areaName || 'Not assigned' }}</dd></dl>
        <h3>Roles</h3><div class="chips">@for (role of user.roleNames; track role) { <span>{{ role }}</span> }</div>
        <h3>Assigned facilities</h3>@if (user.facilities.length) { <ul>@for (facility of user.facilities; track facility.facilityId) { <li>{{ facility.name }} <small>· {{ facility.assignmentRole }}</small></li> }</ul> } @else { <p>No facility assignments.</p> }
        <a mat-stroked-button routerLink="/notifications">View notifications</a>
      </section>
    } @else { <p>Sign in to view your account.</p> }
  `,
  styles: [`
    .profile-card { max-width:720px; padding:1.5rem; border:1px solid #dce3ea; border-radius:10px; background:white }
    .avatar { float:left; width:3.2rem; height:3.2rem; margin-right:1rem; display:grid; place-items:center; border-radius:50%; color:white; background:#0b1f33; font-size:1.2rem; font-weight:700 }
    h2 { margin:0; color:#14212e } p { color:#5b6b7b } dl { display:grid; grid-template-columns:150px 1fr; gap:.6rem; margin:1.5rem 0 } dt { color:#5b6b7b } dd { margin:0; font-weight:600 }
    h3 { margin:1.2rem 0 .6rem; font-size:1rem } .chips { display:flex; gap:.4rem; flex-wrap:wrap } .chips span { padding:.3rem .6rem; border-radius:99px; color:#0a7166; background:#e2f4f1; font-size:.8rem } li { padding:.35rem 0 } li small { color:#5b6b7b }
  `],
})
export class Profile {
  protected readonly session = inject(SessionService);
  initials(name: string): string { return name.split(/\s+/).slice(0, 2).map((part) => part[0] ?? '').join('').toUpperCase(); }
}
