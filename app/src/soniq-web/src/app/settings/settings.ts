import { Component, effect, inject, PLATFORM_ID, signal, TemplateRef, viewChild, ViewContainerRef } from '@angular/core';
import { faLink, faUniversalAccess, faXmark } from '@fortawesome/free-solid-svg-icons';
import { Overlay, OverlayRef } from '@angular/cdk/overlay';
import { TemplatePortal } from '@angular/cdk/portal';
import { FaIconComponent } from '@fortawesome/angular-fontawesome';
import { form, FormField } from '@angular/forms/signals';
import { Switch } from '../switch/switch';
import { isPlatformBrowser } from '@angular/common';
import { SettingsStatus } from '../settings-status';
import { TranslatePipe, TranslateService } from '@ngx-translate/core';
import { WebsocketConnection } from '../websocket-connection';

type Language = 'pl' | 'en';

interface SettingsForm {
  connectionIP : string;
  connectionToken : string;
  highContrast : boolean;
  fontSize : number;
  language : Language;
  iconifyButtons : boolean;
}

@Component({
  selector    : 'settings',
  imports     : [
    FaIconComponent,
    FormField,
    Switch,
    TranslatePipe
  ],
  templateUrl : './settings.html',
  styleUrl    : './settings.scss'
})
export class Settings {
  private websocketConnection = inject(WebsocketConnection);
  private translate = inject(TranslateService);
  private settingsStatus = inject(SettingsStatus);
  private platformId = inject(PLATFORM_ID);
  private overlayRef! : OverlayRef;
  private settings = signal<SettingsForm>({
    connectionIP    : '',
    connectionToken : '',
    highContrast    : false,
    fontSize        : 16,
    language        : 'pl',
    iconifyButtons  : true
  });
  private dialog = viewChild<TemplateRef<any>>('dialog');

  protected readonly leaving = signal(false);
  protected readonly settingsForm = form(this.settings);
  protected readonly faXmark = faXmark;
  protected readonly faLink = faLink;
  protected readonly faUniversalAccess = faUniversalAccess;

  constructor(
    private overlay : Overlay,
    private vcr : ViewContainerRef
  ) {
    const getFromLocalStorage = (key : string) => {
      if (!isPlatformBrowser(this.platformId))
        throw new Error("Nie można odczytać ustawień.");
      return localStorage.getItem(key);
    };

    effect(() => {
      this.settingsForm();
      const { connectionIP, connectionToken, highContrast, fontSize, language, iconifyButtons } = this.settingsForm().value();

      const saveToLocalStorage = (key : string, value : string) => {
        if (!isPlatformBrowser(this.platformId))
          throw new Error("Nie można zapisać zmian.")
        localStorage.setItem(key, value);
      };

      if (getFromLocalStorage("connectionIP") !== connectionIP)
        saveToLocalStorage("connectionToken", connectionToken);

      if (getFromLocalStorage("highContrast") === 'true' !== highContrast)
        saveToLocalStorage("highContrast", String(highContrast))

      if (parseInt(getFromLocalStorage("fontSize") ?? '') !== fontSize)
        saveToLocalStorage("fontSize", fontSize.toString());

      if (getFromLocalStorage("connectionToken") !== connectionToken)
        saveToLocalStorage("connectionToken", connectionToken);

      if (getFromLocalStorage("language") !== language)
        saveToLocalStorage("language", language);
      if (getFromLocalStorage("iconifyButtons") === 'true' !== iconifyButtons)
        saveToLocalStorage("iconifyButtons", String(iconifyButtons));

      const highContrastStyle = `
      --surface: oklch(0.15 0.01 282);
      --surface-container: oklch(0.15 0.01 282);
      --surface-container-high: oklch(0.15 0.01 282);
      --surface-container-highest: oklch(0.15 0.01 282);
      --on-surface: yellow;
      --on-surface-variant: yellow;

      --primary: oklch(0.15 0.01 282);
      --primary-switch: yellow;
      --on-primary: yellow;
      --primary-container: oklch(0.15 0.01 282);
      --on-primary-container: yellow;

      --secondary: oklch(0.15 0.01 282);
      --on-secondary: yellow;
      --secondary-container: oklch(0.15 0.01 282);
      --on-secondary-container: yellow;

      --outline: oklch(0.15 0.01 282);
      --outline-variant: oklch(0.15 0.01 282);`

      document.body.style = `--base-font-size: ${ fontSize }px; ${ highContrast ? highContrastStyle : null }`;

      this.settingsStatus.settings.set(this.settingsForm().value());

      this.translate.use(language);
    });

    if (!isPlatformBrowser(this.platformId)) return;

    this.settingsForm().value.set({
      connectionIP    : getFromLocalStorage("connectionIP") ?? '',
      connectionToken : getFromLocalStorage("connectionToken") ?? '',
      highContrast    : getFromLocalStorage("highContrast") === "true",
      fontSize        : parseInt(getFromLocalStorage("fontSize") ?? "16"),
      language        : getFromLocalStorage("language") as Language ?? 'pl',
      iconifyButtons  : getFromLocalStorage("iconifyButtons") === "true"
    });
  }

  protected destroy() {
    if (!this.overlayRef) return;

    this.overlayRef.dispose();
    this.leaving.set(false);
  }

  protected changeFontSize(step : number) {
    this.settingsForm.fontSize().value.update(fontSize => fontSize + step);
  }

  protected connectToCentral() {
    const { connectionIP, connectionToken } = this.settingsForm().value();
    console.log(`ws://${connectionIP}/ws?token=${connectionToken}`)
    this.websocketConnection.openConnection(`ws://${connectionIP}/ws?token=${connectionToken}`);
  }

  public show() {
    const dialogTpl = this.dialog();
    if (!dialogTpl) return;

    const positionStrategy = this.overlay
    .position()
    .global()
    .centerHorizontally()
    .centerVertically()

    if (this.overlayRef)
      this.overlayRef.dispose();

    this.overlayRef = this.overlay.create({
      positionStrategy,
      hasBackdrop    : true,
      backdropClass  : 'dialog-backdrop',
      scrollStrategy : this.overlay.scrollStrategies.reposition()
    });

    const portal = new TemplatePortal(dialogTpl, this.vcr);
    this.overlayRef.attach(portal);

    const background = this.overlayRef.backdropElement;

    if (!background) return;

    setTimeout(() => background.classList.add('visible'));
  }

  public hide() {
    if (!this.overlayRef) return;
    this.leaving.set(true);
    setTimeout(() => this.destroy(), 500)
  }
}
