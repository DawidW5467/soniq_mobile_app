import { TestBed } from '@angular/core/testing';

import { WebsocketConnection } from './websocket-connection';

describe('WebsocketConnection', () => {
  let service: WebsocketConnection;

  beforeEach(() => {
    TestBed.configureTestingModule({});
    service = TestBed.inject(WebsocketConnection);
  });

  it('should be created', () => {
    expect(service).toBeTruthy();
  });
});
