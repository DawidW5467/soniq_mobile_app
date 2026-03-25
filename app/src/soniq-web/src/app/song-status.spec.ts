import { TestBed } from '@angular/core/testing';

import { SongStatus } from './song-status';

describe('SongStatus', () => {
  let service: SongStatus;

  beforeEach(() => {
    TestBed.configureTestingModule({});
    service = TestBed.inject(SongStatus);
  });

  it('should be created', () => {
    expect(service).toBeTruthy();
  });
});
