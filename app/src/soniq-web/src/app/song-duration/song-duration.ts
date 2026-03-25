import { Component, inject } from '@angular/core';
import { ConvertTimePipe } from '../convert-time-pipe';
import { SongStatus } from '../song-status';
import { TranslatePipe } from '@ngx-translate/core';

@Component({
  selector: 'song-duration',
  imports : [
    ConvertTimePipe,
    TranslatePipe
  ],
  providers : [TranslatePipe],
  templateUrl: './song-duration.html',
  styleUrl: './song-duration.scss',
  host : {
    '[attr.aria-label]': "translatePipe.transform('songDuration.playingPosition')"
  }
})
export class SongDuration {
  protected translatePipe = inject(TranslatePipe);
  protected songService = inject(SongStatus);
}
