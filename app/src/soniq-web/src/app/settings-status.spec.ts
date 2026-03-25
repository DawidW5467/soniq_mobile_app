import { TestBed } from '@angular/core/testing';

import { SettingsStatus } from './settings-status';

describe('SettingsStatus', () => {
  let service: SettingsStatus;

  beforeEach(() => {
    TestBed.configureTestingModule({});
    service = TestBed.inject(SettingsStatus);
  });

  it('should be created', () => {
    expect(service).toBeTruthy();
  });
});
