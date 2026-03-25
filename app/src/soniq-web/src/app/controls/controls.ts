import { Component, computed, inject, PLATFORM_ID } from '@angular/core';
import { FaIconComponent } from '@fortawesome/angular-fontawesome';
import { SongStatus } from '../song-status';
import { faCaretLeft, faCaretRight, faPause, faPlay, faRepeat, faShuffle, faStop } from '@fortawesome/free-solid-svg-icons';
import { isPlatformBrowser } from '@angular/common';
import { SettingsStatus } from '../settings-status';
import { TranslatePipe } from '@ngx-translate/core';

@Component({
  selector: 'controls',
  imports : [
    FaIconComponent,
    TranslatePipe
  ],
  templateUrl: './controls.html',
  styleUrl: './controls.scss',
})
export class Controls {
  private platformId = inject(PLATFORM_ID);
  private settingStatus = inject(SettingsStatus);

  protected songService = inject(SongStatus);

  protected iconifyButtons = computed(() => {
    this.settingStatus.settings();

    if (!isPlatformBrowser(this.platformId))
      return false;
    return localStorage.getItem("iconifyButtons")  === 'true';
  });

  protected readonly faCaretLeft = faCaretLeft;
  protected readonly faPause = faPause;
  protected readonly faPlay = faPlay;
  protected readonly faCaretRight = faCaretRight;
  protected readonly faRepeat = faRepeat;
  protected readonly faShuffle = faShuffle;
  protected readonly faStop = faStop;
}
