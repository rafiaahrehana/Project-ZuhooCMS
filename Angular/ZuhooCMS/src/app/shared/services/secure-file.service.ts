import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { EMPTY, Observable, Subject, defer, of, timer } from 'rxjs';
import { catchError, expand, map, switchMap, take } from 'rxjs/operators';
import { environment } from '../../../environments/environment';

interface Signed { url: string; exp: number; }

/** Refresh a signed link this long before it expires (server validity is 10 minutes). */
const REFRESH_MARGIN_MS = 60_000;
/** Server accepts at most 100 urls per sign request. */
const MAX_BATCH = 100;

/**
 * Turns stored file URLs into URLs a browser can load directly.
 * Public (/api/public/files/{id}) and external/data URLs are just resolved against the API origin.
 * Private (/api/files/{id}, legacy /uploads/{name}) are exchanged via POST /api/files/sign, batched and cached, because an <img>/<a> cannot send the bearer token.
 * Anonymous visitors get the plain resolved URL, so public files load and private ones correctly do not.
 */
@Injectable({ providedIn: 'root' })
export class SecureFileService {
  private readonly apiOrigin = environment.apiUrl.replace(/\/api\/?$/, '');
  private readonly cache = new Map<string, Signed>();
  private readonly waiting = new Map<string, Subject<Signed>>();
  private flushScheduled = false;

  constructor(private http: HttpClient) {}

  /** Emits a loadable URL (and a fresh one before a signed link expires) for a stored file URL. */
  resolve(raw: string | null | undefined): Observable<string | null> {
    if (!raw) return of(null);
    const url = raw.trim();
    if (!url || url.startsWith('data:') || url.startsWith('blob:')) return of(url || null);

    const path = this.apiPath(url);
    if (path === null) return of(url); // external URL - not ours, leave it alone
    if (path.startsWith('/api/public/files/')) return of(this.apiOrigin + path);
    const isPrivate = path.startsWith('/api/files/') || path.startsWith('/uploads/');
    if (!isPrivate || !this.hasToken()) return of(this.apiOrigin + path);

    return defer(() => this.signed(path)).pipe(
      expand(s => Number.isFinite(s.exp)
        ? timer(Math.max(s.exp - REFRESH_MARGIN_MS - Date.now(), 5_000)).pipe(switchMap(() => this.signed(path)))
        : EMPTY),
      map(s => s.url),
    );
  }

  /** '/api/files/1' style path when the URL points at our API (relative or on its origin), else null. */
  private apiPath(url: string): string | null {
    if (url.startsWith('/')) return url.split('?')[0];
    if (url.startsWith(this.apiOrigin + '/')) return url.substring(this.apiOrigin.length).split('?')[0];
    // Legacy rows stored absolute URLs of whatever host served them (e.g. http://localhost:8085/uploads/x).
    const m = /^https?:\/\/[^/]+(\/uploads\/[^/?#]+)$/.exec(url.split('?')[0]);
    return m ? m[1] : null;
  }

  private hasToken(): boolean {
    try {
      return !!localStorage.getItem('access_token');
    } catch {
      return false;
    }
  }

  private signed(path: string): Observable<Signed> {
    const hit = this.cache.get(path);
    if (hit && hit.exp - REFRESH_MARGIN_MS > Date.now()) return of(hit);
    let subject = this.waiting.get(path);
    if (!subject) {
      subject = new Subject<Signed>();
      this.waiting.set(path, subject);
      this.scheduleFlush();
    }
    return subject.pipe(take(1));
  }

  /** Collects every URL requested in the same tick into one (chunked) sign request. */
  private scheduleFlush(): void {
    if (this.flushScheduled) return;
    this.flushScheduled = true;
    setTimeout(() => {
      this.flushScheduled = false;
      const batch = new Map(this.waiting);
      this.waiting.clear();
      const paths = [...batch.keys()];
      for (let i = 0; i < paths.length; i += MAX_BATCH) {
        const chunk = paths.slice(i, i + MAX_BATCH);
        this.http.post<{ signed: Record<string, string> }>(`${environment.apiUrl}/files/sign`, { urls: chunk })
          .pipe(catchError(() => of({ signed: {} as Record<string, string> })))
          .subscribe(res => {
            for (const p of chunk) {
              const signedPath = res?.signed?.[p];
              let result: Signed;
              if (signedPath) {
                const exp = Number(new URLSearchParams(signedPath.split('?')[1] || '').get('exp')) * 1000;
                result = { url: this.apiOrigin + signedPath, exp: exp || Date.now() + REFRESH_MARGIN_MS * 2 };
                this.cache.set(p, result);
              } else {
                // Not readable (or signing failed): fall back to the plain URL, no refresh.
                result = { url: this.apiOrigin + p, exp: Infinity };
              }
              const s = batch.get(p);
              s?.next(result);
              s?.complete();
            }
          });
      }
    }, 0);
  }
}
