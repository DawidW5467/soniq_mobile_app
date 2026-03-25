import { ComponentFixture, TestBed } from '@angular/core/testing';

import { SongCover } from './song-cover';

describe('SongCover', () => {
  let component: SongCover;
  let fixture: ComponentFixture<SongCover>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [SongCover]
    })
    .compileComponents();

    fixture = TestBed.createComponent(SongCover);
    component = fixture.componentInstance;
    await fixture.whenStable();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
