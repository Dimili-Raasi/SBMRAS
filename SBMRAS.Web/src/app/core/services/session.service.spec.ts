import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { of } from 'rxjs';

import { CurrentUser } from '../models/auth.models';
import { ApiService } from './api.service';
import { AuthService } from './auth.service';
import { SessionService } from './session.service';

describe('SessionService', () => {
  it('waits for sign-in redirect handling before deciding the user is anonymous', async () => {
    const auth = { isAuthenticated: false, initialize: async () => { auth.isAuthenticated = true; } };
    const user = { userId: 11, permissions: ['dashboard.view'] } as unknown as CurrentUser;
    const api = jasmine.createSpyObj<ApiService>('ApiService', ['get']);
    api.get.and.returnValue(of(user) as never);

    TestBed.configureTestingModule({
      providers: [provideRouter([]), { provide: AuthService, useValue: auth }, { provide: ApiService, useValue: api }],
    });
    const session = TestBed.inject(SessionService);

    expect(await session.load()).toBe(user);
    expect(session.hasPermission('dashboard.view')).toBeTrue();
    expect(api.get).toHaveBeenCalledOnceWith('me');
  });
});
