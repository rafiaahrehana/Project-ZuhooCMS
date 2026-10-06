import { Injectable } from '@angular/core';
import { BehaviorSubject, Observable, of } from 'rxjs';
import { map, tap } from 'rxjs/operators';
import { ApiService } from './api.service';

// A plain string, not a TS enum: the source of truth is GET /api/users/permissions, not a list duplicated on both sides.
export type PermissionCode = string;

/**
 * Caches GET /api/users/permissions so hasPermission() can be answered synchronously - RoleGuard needs it populated before it evaluates, not fetched on first check.
 * Backed by localStorage so the set survives a page refresh like the logged-in User does.
 */
@Injectable({ providedIn: 'root' })
export class PermissionService {
  private readonly STORAGE_KEY = 'permissions';
  private readonly CATALOG_STORAGE_KEY = 'permission_catalog';

  private permissionsSubject = new BehaviorSubject<string[]>(this.getFromStorage(this.STORAGE_KEY));
  public permissions$ = this.permissionsSubject.asObservable();

  // True once load() resolved this page session; the localStorage set can be stale (previous account), so guards must not trust it before then. See ensureLoaded().
  private loaded = false;

  // Full catalog (GET /api/permissions), used only to decide whether a user holds every existing permission - see hasAllPermissions().
  private catalogSubject = new BehaviorSubject<string[]>(this.getFromStorage(this.CATALOG_STORAGE_KEY));
  public catalog$ = this.catalogSubject.asObservable();

  constructor(private api: ApiService) {}

  /** Fetches the current user's permission set from the backend and caches it. */
  load(): Observable<string[]> {
    return this.api.get<string[]>('/users/permissions').pipe(
      tap(permissions => {
        this.permissionsSubject.next(permissions);
        this.loaded = true;
        localStorage.setItem(this.STORAGE_KEY, JSON.stringify(permissions));
      }),
    );
  }

  /** RoleGuard awaits this so a hard reload into a gated route cannot 403 on the stale localStorage set while load() is still in flight. */
  ensureLoaded(): Observable<string[]> {
    if (this.loaded) return of(this.permissionsSubject.value);
    return this.load();
  }

  /** Fetches the full permission catalog and caches it. See catalogSubject above. */
  loadCatalog(): Observable<string[]> {
    return this.api.get<{ code: string }[]>('/permissions').pipe(
      map(list => list.map(p => p.code)),
      tap(codes => {
        this.catalogSubject.next(codes);
        localStorage.setItem(this.CATALOG_STORAGE_KEY, JSON.stringify(codes));
      }),
    );
  }

  hasPermission(permission: PermissionCode | null | undefined): boolean {
    if (!permission) return true;
    return this.permissionsSubject.value.includes(permission);
  }

  hasAnyPermission(permissions: PermissionCode[] | null | undefined): boolean {
    if (!permissions || permissions.length === 0) return true;
    const mine = this.permissionsSubject.value;
    return permissions.some(p => mine.includes(p));
  }

  /** True only once the catalog has loaded and the user's set covers every known code. */
  hasAllPermissions(): boolean {
    const all = this.catalogSubject.value;
    if (!all.length) return false;
    const mine = new Set(this.permissionsSubject.value);
    return all.every(code => mine.has(code));
  }

  /** Clears the cached sets. Called on logout (see AuthService.clearSession()). */
  clear(): void {
    this.permissionsSubject.next([]);
    this.catalogSubject.next([]);
    this.loaded = false;
    localStorage.removeItem(this.STORAGE_KEY);
    localStorage.removeItem(this.CATALOG_STORAGE_KEY);
  }

  private getFromStorage(key: string): string[] {
    const raw = localStorage.getItem(key);
    if (!raw) return [];
    try {
      return JSON.parse(raw);
    } catch {
      return [];
    }
  }
}
