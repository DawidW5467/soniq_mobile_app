import { Injectable, signal } from '@angular/core';

type LoopMode = 'off' | 'all' | 'one' | 'cycle';

interface SongData {
  id : string;
  title : string;
  artist : string;
  album : string;
  duration : number;
  cover? : Blob;
}

interface ConsoleStatus {
  connected : boolean;
  playing : boolean;
  volume : number;
  loop : LoopMode;
  shuffle : boolean;
  position : number;
  currentPosition? : number;
}

@Injectable({
  providedIn: 'root',
})
export class SongStatus {
  public song = signal<SongData>({
    id: '',
    title: '',
    artist: '',
    album: '',
    duration: 0,
  });

  public consoleStatus = signal<ConsoleStatus>({
    connected: false,
    playing: false,
    volume: 50,
    loop: 'off',
    shuffle: false,
    position: 0,
  });
}
