import { Component, computed, inject, PLATFORM_ID, viewChild } from '@angular/core';
import { SongCover } from './song-cover/song-cover';
import { SongDuration } from './song-duration/song-duration';
import { Controls } from './controls/controls';
import { FaIconComponent } from '@fortawesome/angular-fontawesome';
import { faGear } from '@fortawesome/free-solid-svg-icons';
import { Settings } from './settings/settings';
import { TranslatePipe, TranslateService } from '@ngx-translate/core';
import { isPlatformBrowser } from '@angular/common';
import plTranslations from '../assets/i18n/pl.json';
import enTranslations from '../assets/i18n/en.json';
import { SettingsStatus } from './settings-status';

@Component({
  selector    : 'app-root',
  imports : [
    SongCover,
    SongDuration,
    Controls,
    FaIconComponent,
    Settings,
    TranslatePipe
  ],
  templateUrl : './app.html',
  styleUrl    : './app.scss'
})
export class App {
  private platformId = inject(PLATFORM_ID);
  private settingsStatus = inject(SettingsStatus);
  private settings = viewChild(Settings);
  private translate = inject(TranslateService);
  protected readonly faGear = faGear;

  protected iconifyButtons = computed(() => {
    this.settingsStatus.settings();

    if (!isPlatformBrowser(this.platformId)) return true;

    return localStorage.getItem("iconifyButtons") === "true";
  });

  constructor() {
    this.translate.addLangs(['pl', 'en']);
    this.translate.setFallbackLang('pl');
    this.translate.setTranslation('pl', plTranslations);
    this.translate.setTranslation('en', enTranslations);

    if (!isPlatformBrowser(this.platformId)) {
      this.translate.use('pl');
      return;
    }

    const language = localStorage.getItem('language') ?? 'pl';
    this.translate.use(language);
  }

  protected openSettings() {
    const settings = this.settings();
    if (!settings) return;
    settings.show();
  }
}
