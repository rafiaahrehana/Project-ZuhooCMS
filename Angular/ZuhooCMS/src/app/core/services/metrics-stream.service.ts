import { Injectable, NgZone } from '@angular/core';
import { Observable } from 'rxjs';
import { environment } from '../../../environments/environment';

@Injectable({
  providedIn: 'root'
})
export class MetricsStreamService {

  constructor(private ngZone: NgZone) {}

  /** SSE stream; runOutsideAngular keeps the 500ms tick from triggering change detection. */
  public getTrafficStream(): Observable<number> {
    return new Observable(observer => {
      const eventSource = new EventSource(`${environment.apiUrl}/v1/metrics/stream`);

      eventSource.onmessage = (event) => {
        // MUST run outside Angular to avoid change detection thrashing.
        this.ngZone.runOutsideAngular(() => {
          const trafficValue = parseInt(event.data, 10);
          observer.next(trafficValue);
        });
      };

      eventSource.onerror = (error) => {
        console.error('SSE connection error, closing stream', error);
        this.ngZone.run(() => observer.error(error));
        eventSource.close();
      };

      return () => {
        eventSource.close();
      };
    });
  }
}
