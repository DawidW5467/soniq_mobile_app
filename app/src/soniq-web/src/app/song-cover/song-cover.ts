import { Component, computed, inject, PLATFORM_ID } from '@angular/core';
import { FaIconComponent } from '@fortawesome/angular-fontawesome';
import { isPlatformBrowser, NgOptimizedImage } from '@angular/common';
import { faMusic } from '@fortawesome/free-solid-svg-icons';
import { SongStatus } from '../song-status';
import { SettingsStatus } from '../settings-status';
import { TranslatePipe } from '@ngx-translate/core';

@Component({
  selector: 'song-cover',
  imports : [
    FaIconComponent,
    NgOptimizedImage,
    TranslatePipe
  ],
  templateUrl: './song-cover.html',
  styleUrl: './song-cover.scss',
})
export class SongCover {
  private settingStatus = inject(SettingsStatus);
  private platformId = inject(PLATFORM_ID);
  protected songService = inject(SongStatus);

  protected songCoverGrayscale = computed(() => {
    this.settingStatus.settings();
    if (!isPlatformBrowser(this.platformId))
      return false;

    return localStorage.getItem('highContrast') === 'true';
  });

  protected readonly faMusic = faMusic;
}
