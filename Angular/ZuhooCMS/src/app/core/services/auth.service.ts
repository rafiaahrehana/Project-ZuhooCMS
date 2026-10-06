import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Router } from '@angular/router';
import { BehaviorSubject, Observable, throwError } from 'rxjs';
import { map, tap, catchError, switchMap, shareReplay } from 'rxjs/operators';
import { PermissionService } from './permission.service';
import {
  LoginRequest,
  LoginResponse,
  JwtResponse,
  RegisterRequest,
  VerifyEmailRequest,
  ResendVerificationRequest,
  ForgotPasswordRequest,
  VerifyResetCodeRequest,
  ResetPasswordRequest,
  ChangePasswordRequest,
  User,
  TokenPayload,
  ImpersonationResponse,
  ImpersonationSession,
} from '../models/auth.model';
import { environment } from '../../../environments/environment';

// SaaS-provider staff roles, not Company-scoped ones; must mirror backend User.isPlatformUser().
const PLATFORM_ROLES = [
  'SUPER_ADMIN', 'SYSTEM_ADMIN', 'SUPPORT_AGENT', 'SUPPORT_MANAGER',
  'MARKETING_MANAGER', 'PLATFORM_ACCOUNTANT', 'SALES_MANAGER',
];

@Injectable({
  providedIn: 'root'
})
export class AuthService {
  private readonly API_URL = `${environment.apiUrl}/auth`;
  private readonly TOKEN_KEY = 'access_token';
  private readonly REFRESH_TOKEN_KEY = 'refresh_token';
  private readonly USER_KEY = 'user';

  private readonly ADMIN_TOKEN_KEY = 'admin_access_token';
  private readonly ADMIN_USER_KEY = 'admin_user';
  private readonly IMPERSONATION_KEY = 'impersonation_session';

  private currentUserSubject = new BehaviorSubject<User | null>(this.getUserFromStorage());
  public currentUser$ = this.currentUserSubject.asObservable();

  private isAuthenticatedSubject = new BehaviorSubject<boolean>(this.hasValidToken());
  public isAuthenticated$ = this.isAuthenticatedSubject.asObservable();

  private impersonationSubject = new BehaviorSubject<ImpersonationSession | null>(this.getImpersonationFromStorage());
  public impersonation$ = this.impersonationSubject.asObservable();

  constructor(
    private http: HttpClient,
    private router: Router,
    private permissionService: PermissionService,
  ) {
    this.initializeAuthState();
  }

  isPlatformUser(): boolean {
    const user = this.currentUserSubject.value;
    return !!user && user.roles.some(r => PLATFORM_ROLES.includes(r));
  }

  isImpersonating(): boolean {
    return this.impersonationSubject.value !== null;
  }

  getImpersonationSession(): ImpersonationSession | null {
    return this.impersonationSubject.value;
  }

  startImpersonation(response: ImpersonationResponse): void {
    const adminUser = this.currentUserSubject.value;
    if (adminUser) {
      localStorage.setItem(this.ADMIN_USER_KEY, JSON.stringify(adminUser));
    }
    const adminToken = this.getAccessToken();
    if (adminToken) {
      localStorage.setItem(this.ADMIN_TOKEN_KEY, adminToken);
    }

    const impersonatedUser: User = {
      id: adminUser?.id ?? 0,
      username: adminUser?.username ?? '',
      email: adminUser?.email ?? '',
      fullName: adminUser?.fullName ?? '',
      roles: ['COMPANY_OWNER'],
      companyId: response.companyId,
    };

    localStorage.setItem(this.TOKEN_KEY, response.accessToken);
    this.setUserInStorage(impersonatedUser);
    this.currentUserSubject.next(impersonatedUser);

    const session: ImpersonationSession = {
      companyId: response.companyId,
      companyName: response.companyName,
      impersonationSessionId: response.impersonationSessionId,
      expiresAt: Date.now() + response.expiresInSeconds * 1000,
    };
    localStorage.setItem(this.IMPERSONATION_KEY, JSON.stringify(session));
    this.impersonationSubject.next(session);

    this.router.navigate(['/']);
  }


  endImpersonation(): Observable<any> {
    const session = this.impersonationSubject.value;
    const restore = () => {
      const adminUserRaw = localStorage.getItem(this.ADMIN_USER_KEY);
      const adminToken = localStorage.getItem(this.ADMIN_TOKEN_KEY);

      localStorage.removeItem(this.ADMIN_USER_KEY);
      localStorage.removeItem(this.ADMIN_TOKEN_KEY);
      localStorage.removeItem(this.IMPERSONATION_KEY);
      this.impersonationSubject.next(null);

      if (adminToken) {
        localStorage.setItem(this.TOKEN_KEY, adminToken);
      }
      if (adminUserRaw && adminUserRaw !== 'undefined') {
        const adminUser = JSON.parse(adminUserRaw) as User;
        this.setUserInStorage(adminUser);
        this.currentUserSubject.next(adminUser);
      }
      this.router.navigate(['/']);
    };

    // shareReplay makes this one hot execution shared by every subscriber: the returned observable is cold otherwise, so a
    // caller that subscribed fired a SECOND POST /impersonate/end and ran restore() twice on top of an already-restored session.
    const request$ = this.http
      .post(
        `${environment.apiUrl}/platform-admin/impersonate/end`,
        session ? { impersonationSessionId: session.impersonationSessionId } : {},
      )
      .pipe(shareReplay({ bufferSize: 1, refCount: false }));

    if (session) {
      request$.subscribe({ next: restore, error: restore });
    } else {
      // No session to end server-side, but the local admin session still has to come back; the call is still made and shared.
      restore();
      request$.subscribe({ next: () => {}, error: () => {} });
    }
    return request$;
  }

  private getImpersonationFromStorage(): ImpersonationSession | null {
    const raw = localStorage.getItem(this.IMPERSONATION_KEY);
    return (raw && raw !== 'undefined') ? JSON.parse(raw) : null;
  }
 
  login(credentials: LoginRequest): Observable<User> {
    let loggedInUser!: User;
    return this.http.post<LoginResponse>(`${this.API_URL}/login`, credentials).pipe(
      tap(response => {
        loggedInUser = {
          id: response.userId,
          username: response.email,
          email: response.email,
          fullName: response.firstName,
          roles: [response.role],
          companyId: response.companyId
        };
        this.setTokens(response.accessToken, response.refreshToken);
        this.setUserInStorage(loggedInUser);
        this.currentUserSubject.next(loggedInUser);
        this.isAuthenticatedSubject.next(true);
      }),
      // Permissions must be cached before the caller navigates: route guards read them synchronously.
      switchMap(() => this.permissionService.load()),
      switchMap(() => this.permissionService.loadCatalog()),
      switchMap(() => this.getProfile()),
      tap(profile => {
        loggedInUser.fullName = this.displayName(profile, loggedInUser.fullName);
        loggedInUser.profileImageUrl = this.resolveImageUrl(profile.image);
        this.setUserInStorage(loggedInUser);
        this.currentUserSubject.next(loggedInUser);
      }),
      map(() => loggedInUser),
      catchError(error => {
        console.error('Login failed', error);
        return throwError(() => error);
      })
    );
  }

  /** No login here: the account stays inactive until /auth/verify-email is called. */
  register(request: RegisterRequest): Observable<any> {
    return this.http.post<any>(`${this.API_URL}/register`, request);
  }

  verifyEmail(request: VerifyEmailRequest): Observable<any> {
    return this.http.post(`${this.API_URL}/verify-email`, request, { responseType: 'text' });
  }

  /** Always 200 regardless of whether the email exists - no user enumeration. */
  resendVerification(request: ResendVerificationRequest): Observable<any> {
    return this.http.post(`${this.API_URL}/resend-verification`, request, { responseType: 'text' });
  }

  /** Always 200 (no email enumeration); calling again issues a fresh code and invalidates the old one. */
  forgotPassword(request: ForgotPasswordRequest): Observable<any> {
    return this.http.post(`${this.API_URL}/forgot-password`, request, { responseType: 'text' });
  }

  /** Pre-check only: does not consume the code - resetPassword() re-validates it for real. */
  verifyResetCode(request: VerifyResetCodeRequest): Observable<any> {
    return this.http.post(`${this.API_URL}/verify-reset-code`, request, { responseType: 'text' });
  }

  /** Takes the 6-digit code or a client-portal invite token (see ResetPasswordRequest); revokes all refresh tokens server-side. */
  resetPassword(request: ResetPasswordRequest): Observable<any> {
    return this.http.post(`${this.API_URL}/reset-password`, request, { responseType: 'text' });
  }

  /** Revokes ALL refresh tokens, so the caller must logout() and return to the login page afterwards. */
  changePassword(request: ChangePasswordRequest): Observable<any> {
    return this.http.post(`${this.API_URL}/change-password`, request, { responseType: 'text' });
  }

  /** Set while the session came from "See Demo" - the read-only banner keys off it. */
  private readonly DEMO_KEY = 'bos-demo';

  isDemoSession(): boolean {
    try { return localStorage.getItem(this.DEMO_KEY) === '1'; } catch { return false; }
  }

  /** Public read-only demo: no credentials, 45-minute token; caches permissions first because guards read them synchronously. */
  startDemo(): Observable<User> {
    let demoUser!: User;
    return this.http.post<LoginResponse>(`${environment.apiUrl}/public/demo/session`, {}).pipe(
      tap(response => {
        demoUser = {
          id: response.userId,
          username: response.email,
          email: response.email,
          fullName: response.firstName,
          roles: [response.role],
          companyId: response.companyId
        };
        // No refresh token by design: when the access token dies, the demo is over.
        localStorage.setItem(this.TOKEN_KEY, response.accessToken);
        localStorage.setItem(this.DEMO_KEY, '1');
        this.setUserInStorage(demoUser);
        this.currentUserSubject.next(demoUser);
        this.isAuthenticatedSubject.next(true);
      }),
      switchMap(() => this.permissionService.load()),
      switchMap(() => this.permissionService.loadCatalog()),
      map(() => demoUser),
    );
  }

  /** Leave the demo: wipe the session and land back on the marketing page. */
  exitDemo(): void {
    this.clearSession();
    this.router.navigate(['/home']);
  }

  logout(): void {
    const refreshToken = this.getRefreshToken();

    if (refreshToken) {
      // Before clearSession() so the interceptor still attaches the access token, which the server then revokes too.
      this.http.post(`${this.API_URL}/logout`, { refreshToken }, { responseType: 'text' }).subscribe({ error: () => {} });
    }

    this.clearSession();
    this.router.navigate(['/auth/login']);
  }

  /** Clears local session state without navigating; AuthGuard uses it to purge a server-rejected refresh token. */
  clearSession(): void {
    this.clearTokens();
    this.clearUserStorage();
    localStorage.removeItem(this.DEMO_KEY);
    localStorage.removeItem(this.ADMIN_TOKEN_KEY);
    localStorage.removeItem(this.ADMIN_USER_KEY);
    localStorage.removeItem(this.IMPERSONATION_KEY);
    this.impersonationSubject.next(null);
    this.currentUserSubject.next(null);
    this.isAuthenticatedSubject.next(false);
    this.permissionService.clear();
  }
 
  /**
   * /auth/refresh returns no user info, so the stored user object must be left as-is.
   * Does NOT log out on failure - a failure can just mean the backend was briefly unreachable; AuthInterceptor decides by status code.
   */
  refreshToken(): Observable<JwtResponse> {
    const refreshToken = this.getRefreshToken();
    return this.http.post<JwtResponse>(`${this.API_URL}/refresh`, {
      refreshToken
    }).pipe(
      tap(response => {
        this.setTokens(response.accessToken, response.refreshToken);
        this.isAuthenticatedSubject.next(true);
        const user = this.getUserFromStorage();
        if (user) {
          this.currentUserSubject.next(user);
        }
        this.permissionService.load().subscribe({ error: () => {} });
        this.permissionService.loadCatalog().subscribe({ error: () => {} });
      })
    );
  }

  getAccessToken(): string | null {
    return localStorage.getItem(this.TOKEN_KEY);
  }
 
  getRefreshToken(): string | null {
    return localStorage.getItem(this.REFRESH_TOKEN_KEY);
  }
 
  isAuthenticated(): boolean {
    return this.hasValidToken();
  }
 
  hasRole(role: string): boolean {
    const user = this.currentUserSubject.value;
    return user ? user.roles.includes(role) : false;
  }
 
  hasAnyRole(roles: string[]): boolean {
    const user = this.currentUserSubject.value;
    if (!user) return false;
    return roles.some(role => user.roles.includes(role));
  }

  isPlatformStaff(): boolean {
    const user = this.currentUserSubject.value;
    if (!user) return false;
    return user.roles.some(role => PLATFORM_ROLES.includes(role));
  }
 
  getCurrentUser(): User | null {
    return this.currentUserSubject.value;
  }
 
  getCompanyId(): number | null {
    const user = this.currentUserSubject.value;
    return user?.companyId || null;
  }
 
  private decodeToken(): TokenPayload | null {
    const token = this.getAccessToken();
    if (!token) return null;
 
    try {
      const base64Url = token.split('.')[1];
      const base64 = base64Url.replace(/-/g, '+').replace(/_/g, '/');
      const jsonPayload = decodeURIComponent(
        atob(base64).split('').map(c => '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2)).join('')
      );
      return JSON.parse(jsonPayload);
    } catch (error) {
      console.error('Error decoding token', error);
      return null;
    }
  }
 
  private hasValidToken(): boolean {
    const token = this.getAccessToken();
    if (!token) return false;
 
    const payload = this.decodeToken();
    if (!payload) return false;
 
    const currentTime = Date.now() / 1000;
    return payload.exp > currentTime;
  }
 
  private setTokens(accessToken: string, refreshToken: string): void {
    localStorage.setItem(this.TOKEN_KEY, accessToken);
    localStorage.setItem(this.REFRESH_TOKEN_KEY, refreshToken);
  }
 
  private clearTokens(): void {
    localStorage.removeItem(this.TOKEN_KEY);
    localStorage.removeItem(this.REFRESH_TOKEN_KEY);
  }
 
  getProfile(): Observable<any> {
    return this.http.get<any>(`${environment.apiUrl}/users/profile`);
  }

  updateProfile(request: any): Observable<any> {
    return this.http.patch<any>(`${environment.apiUrl}/users/profile`, request).pipe(
      tap(profile => {
        const storedUser = this.getUserFromStorage();
        if (storedUser) {
          storedUser.fullName = this.displayName(profile, storedUser.fullName);
          storedUser.profileImageUrl = this.resolveImageUrl(profile.image);
          this.setUserInStorage(storedUser);
          this.currentUserSubject.next(storedUser);
        }
      })
    );
  }

  /** Refreshes the cached avatar after an image change outside /users/profile (e.g. PATCH /api/employees/me), which AuthService never sees. */
  updateCurrentUserImage(imageUrl: string | null | undefined): void {
    const storedUser = this.getUserFromStorage();
    if (!storedUser) return;
    storedUser.profileImageUrl = this.resolveImageUrl(imageUrl);
    this.setUserInStorage(storedUser);
    this.currentUserSubject.next(storedUser);
  }

  private setUserInStorage(user: User): void {
    localStorage.setItem(this.USER_KEY, JSON.stringify(user));
  }
 
  private getUserFromStorage(): User | null {
    const user = localStorage.getItem(this.USER_KEY);
    const parsed: User | null = (user && user !== 'undefined') ? JSON.parse(user) : null;
    // Anyone who signed in before displayName() existed may still be carrying a name built from
    // missing fields. It is cached, so it outlives the bug unless it is dropped on the way out.
    if (parsed?.fullName?.includes('undefined')) {
      parsed.fullName = parsed.email ?? parsed.username ?? '';
    }
    return parsed;
  }
 
  private clearUserStorage(): void {
    localStorage.removeItem(this.USER_KEY);
  }
 
  /**
   * A display name from a profile, never the string "undefined undefined".
   *
   * Template-joining first and last name writes that literal into storage when either is missing, and
   * because it is cached it survives a refresh - the greeting then reads "Welcome, undefined!" until
   * the profile is fetched again with both fields present. Falls back to the email, then to whatever
   * name we already had, so a partial profile degrades to something true rather than to nonsense.
   */
  private displayName(profile: any, existing?: string): string {
    const joined = [profile?.firstName, profile?.lastName]
      .filter(part => typeof part === 'string' && part.trim().length > 0)
      .join(' ')
      .trim();
    return joined || profile?.email?.trim() || existing?.trim() || '';
  }

  resolveImageUrl(url: string | undefined | null): string | undefined {
    if (!url) return undefined;
    if (url.startsWith('http://') || url.startsWith('https://') || url.startsWith('data:')) {
      return url;
    }
    const base = environment.apiUrl.replace(/\/api$/, '');
    const cleanUrl = url.startsWith('/') ? url : `/${url}`;
    return `${base}${cleanUrl}`;
  }

  private initializeAuthState(): void {
    const user = this.getUserFromStorage();
    if (user) {
      this.currentUserSubject.next(user);
    }

    const isAuthenticated = this.hasValidToken();
    this.isAuthenticatedSubject.next(isAuthenticated);

    if (isAuthenticated) {
      // Deferred to a macrotask: authInterceptor injects AuthService per request, so firing these inside the constructor throws NG0200.
      setTimeout(() => {
        this.permissionService.load().subscribe({ error: () => {} });
        this.permissionService.loadCatalog().subscribe({ error: () => {} });
        this.getProfile().subscribe({
          next: (profile) => {
            const activeUser: User = user || {
              id: profile.id,
              username: profile.email,
              email: profile.email,
              fullName: this.displayName(profile),
              roles: [profile.role],
              companyId: null
            };
            activeUser.fullName = this.displayName(profile, activeUser.fullName);
            activeUser.profileImageUrl = this.resolveImageUrl(profile.image);
            this.setUserInStorage(activeUser);
            this.currentUserSubject.next(activeUser);
          }
        });
      }, 0);
    }
  }
}