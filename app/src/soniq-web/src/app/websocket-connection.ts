import { effect, Injectable, signal } from '@angular/core';

@Injectable({
  providedIn : 'root'
})
export class WebsocketConnection {
  public websocket = signal<WebSocket | null>(null);
  public message = signal<any | null>(null);

  constructor() {
    effect(() => {
      if (!this.websocket()) return;

      this.websocket()!.addEventListener('message', (message) => {
        this.message.set(message);
      });

      this.websocket()!.addEventListener('open', () => {
        console.log("Połączenie jest aktywne.");
      });
    });
  }

  public openConnection(url : string) {
    this.websocket.set(new WebSocket(url));
  }

  public sendPacket(packet : any) {
    if (!this.websocket()) throw new Error('Nie ma aktywnego połączenia');
    this.websocket()!.send(packet);
  }
}
