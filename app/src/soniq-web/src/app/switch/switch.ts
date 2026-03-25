import { Component, input, model } from '@angular/core';
import { faCheck, faXmark } from '@fortawesome/free-solid-svg-icons';
import { FormCheckboxControl } from "@angular/forms/signals";

@Component({
  selector  : 'switch',
  templateUrl : './switch.html',
  styleUrl : './switch.scss',
  providers : [],
  host      : {
    '[class.on]'  : "checked()",
    '[class.off]' : "!checked()",
  }
})
export class Switch implements FormCheckboxControl {
  public checked = model<boolean>(false);

  public label = input.required<string>();
  protected readonly icons = {
    faXmark,
    faCheck,
  };

  constructor() {}

  protected changeStep() {
    this.checked.update(checked => !checked);
  }
}
