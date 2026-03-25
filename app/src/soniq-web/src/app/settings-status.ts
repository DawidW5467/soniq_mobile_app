import { Injectable, signal } from '@angular/core';

type Language = 'pl' | 'en';

interface SettingsForm {
  connectionIP : string;
  connectionToken : string;
  highContrast : boolean;
  fontSize : number;
  language : Language;
  iconifyButtons : boolean;
}


@Injectable({
  providedIn: 'root',
})
export class SettingsStatus {
  public settings = signal<SettingsForm>({
    connectionIP : '',
    connectionToken : '',
    highContrast : false,
    fontSize : 16,
    language : 'pl',
    iconifyButtons : true
  });
}
