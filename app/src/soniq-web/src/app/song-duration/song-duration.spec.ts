import { ComponentFixture, TestBed } from '@angular/core/testing';

import { SongDuration } from './song-duration';

describe('SongDuration', () => {
  let component: SongDuration;
  let fixture: ComponentFixture<SongDuration>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [SongDuration]
    })
    .compileComponents();

    fixture = TestBed.createComponent(SongDuration);
    component = fixture.componentInstance;
    await fixture.whenStable();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
