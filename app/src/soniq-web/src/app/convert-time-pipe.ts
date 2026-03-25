import { Pipe, PipeTransform } from '@angular/core';

@Pipe({
  name: 'convertTime',
})
export class ConvertTimePipe implements PipeTransform {

  transform(time : number) {
    const hours = Math.floor(time / 3600);
    const minutes = Math.floor((time % 3600) / 60);
    const seconds = Math.floor(time % 60);

    const hoursStr = hours > 0 ? String(hours).padStart(2, '0') + ':' : '';
    const minutesStr = String(minutes).padStart(2, '0') + ':';
    const secondsStr = String(seconds).padStart(2, '0');

    return hoursStr + minutesStr + secondsStr;
  }
}
