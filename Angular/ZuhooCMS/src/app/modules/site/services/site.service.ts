import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpErrorResponse } from '@angular/common/http';
import { Observable, catchError, of, switchMap, throwError } from 'rxjs';
import { environment } from '../../../../environments/environment';
import {
  SiteSettings, NavItem, Service, BlogPost, Testimonial,
  Faq, TeamMember, Project, PricingPlan, Stat, CmsPage,
  ServiceRequestPayload, TrackedRequest
} from '../models/site.model';

/**
 * Every method propagates its HTTP error to the caller on purpose.
 *
 * This service used to catchError each call and substitute a DEFAULT_* fixture, so with the backend down
 * /portal/{slug} rendered a complete invented company - name, email, mission, testimonials, team - that a
 * visitor could not tell from the tenant's real content, and an unknown service slug rendered a plausible
 * wrong service page. A page that cannot load must say so; see SiteNoticeComponent, which every page here
 * shows from its error callback.
 *
 * The one exception is a 404 on a single-item lookup: "no such slug" is a real answer, not a failure, so it
 * becomes null and the page renders its not-found state.
 */
/**
 * Host labels that are the platform's own, not a tenant's.
 *
 * Copied from the backend's own list so the two cannot disagree: identity-service's
 * `SubdomainRules.RESERVED` (services/identity-service/.../company/SubdomainRules.java), which rejects
 * these on sign-up and on admin-created companies. Because no company can own one of these names, a host
 * whose leading label is in this set carries no tenant, so the site falls back to the /portal/{slug} path.
 *
 * If a name is added there, add it here too.
 */
const RESERVED_HOST_LABELS = new Set<string>([
  'www', 'app', 'api', 'admin', 'administrator', 'demo', 'mail', 'email', 'smtp', 'imap', 'pop', 'ftp',
  'static', 'assets', 'files', 'file', 'uploads', 'media', 'img', 'images', 'cdn', 'support', 'help',
  'helpdesk', 'status', 'docs', 'doc', 'blog', 'portal', 'auth', 'login', 'logout', 'signin', 'signup',
  'register', 'account', 'accounts', 'billing', 'payment', 'payments', 'dashboard', 'gateway', 'internal',
  'system', 'root', 'platform', 'superadmin', 'staff', 'dev', 'test', 'staging', 'prod', 'production',
  'localhost', 'ns1', 'ns2', 'dns', 'vpn', 'webmail', 'secure', 'security', 'zuhoo', 'zuhoocms',
]);

@Injectable({ providedIn: 'root' })
export class SiteService {
  private http = inject(HttpClient);
  private api = environment.apiUrl;

  /**
   * The leading label of a named host, or '' when the host carries no tenant name.
   *
   * An IP literal has dots but no subdomain: on 127.0.0.1 a bare parts.length > 2 test returned "127",
   * which the backend rejects as an unknown tenant and which also made getBasePath() drop the
   * /portal/{slug} prefix, so every internal link escaped the site into the admin routes.
   *
   * A reserved label is not a subdomain either: on www.yourdomain.com/portal/demo this returned "www", so
   * the backend was asked for a tenant named "www" and getBasePath() returned '', dropping the
   * /portal/demo prefix from every internal link exactly as the IP case did.
   */
  private get hostSubdomain(): string {
    const host = window.location.hostname;
    // IPv6 hosts are bracketed and contain ':'; IPv4 literals are all digits and dots.
    if (host.includes(':') || /^[\d.]+$/.test(host)) return '';
    const parts = host.split('.');
    if (parts.length <= 2) return '';
    const label = parts[0].toLowerCase();
    return RESERVED_HOST_LABELS.has(label) ? '' : parts[0];
  }

  private get subdomain(): string {
    const fromHost = this.hostSubdomain;
    if (fromHost) return fromHost;
    // window.location.pathname, not router.url: on initial load router.url can still read '/', dropping the subdomain param and making the backend reject requests as "Tenant not identified".
    const match = window.location.pathname.match(/^\/portal\/([^/?]+)/);
    return match ? match[1] : '';
  }

  private params(subdomain?: string): Record<string, string> {
    const s = subdomain || this.subdomain;
    return s ? { subdomain: s } : {};
  }

  /** Prefix for internal site routerLinks: '' on a subdomain deployment, or "/portal/{subdomain}" path-based, where a bare "/services" would escape the nesting into the admin app's routes. */
  getBasePath(): string {
    if (this.hostSubdomain) return '';
    const match = window.location.pathname.match(/^\/portal\/([^/?]+)/);
    return match ? `/portal/${match[1]}` : '';
  }

  /** 404 -> null (the slug does not exist); every other status stays an error, so "unavailable" is never shown as "not found". */
  private notFoundAsNull<T>(source: Observable<T>): Observable<T | null> {
    return source.pipe(
      catchError((err: unknown) =>
        err instanceof HttpErrorResponse && err.status === 404 ? of(null) : throwError(() => err)),
    );
  }

  getSettings(): Observable<SiteSettings> {
    return this.http.get<SiteSettings>(`${this.api}/website/settings`, { params: this.params() });
  }

  getNav(): Observable<NavItem[]> {
    return this.http.get<NavItem[]>(`${this.api}/website/nav`, { params: this.params() });
  }

  getServices(category?: string, q?: string): Observable<Service[]> {
    const p: Record<string, string> = { ...this.params() };
    if (category) p['category'] = category;
    if (q) p['q'] = q;
    return this.http.get<Service[]>(`${this.api}/website/services`, { params: p });
  }

  getService(slug: string): Observable<Service | null> {
    return this.notFoundAsNull(
      this.http.get<Service>(`${this.api}/website/services/${slug}`, { params: this.params() }));
  }

  getBlogs(category?: string): Observable<BlogPost[]> {
    const p: Record<string, string> = { ...this.params() };
    if (category) p['category'] = category;
    return this.http.get<BlogPost[]>(`${this.api}/website/blog`, { params: p });
  }

  getBlog(slug: string): Observable<BlogPost | null> {
    return this.notFoundAsNull(
      this.http.get<BlogPost>(`${this.api}/website/blog/${slug}`, { params: this.params() }));
  }

  getTestimonials(): Observable<Testimonial[]> {
    return this.http.get<Testimonial[]>(`${this.api}/website/testimonials`, { params: this.params() });
  }

  getFaqs(): Observable<Faq[]> {
    return this.http.get<Faq[]>(`${this.api}/website/faqs`, { params: this.params() });
  }

  getTeam(): Observable<TeamMember[]> {
    return this.http.get<TeamMember[]>(`${this.api}/website/team`, { params: this.params() });
  }

  getProjects(): Observable<Project[]> {
    return this.http.get<Project[]>(`${this.api}/website/projects`, { params: this.params() });
  }

  getPricing(): Observable<PricingPlan[]> {
    return this.http.get<PricingPlan[]>(`${this.api}/website/pricing`, { params: this.params() });
  }

  getStats(): Observable<Stat[]> {
    return this.http.get<Stat[]>(`${this.api}/website/stats`, { params: this.params() });
  }

  getPage(slug: string): Observable<CmsPage | null> {
    return this.notFoundAsNull(
      this.http.get<CmsPage>(`${this.api}/website/pages/${slug}`, { params: this.params() }));
  }

  submitContact(body: { name: string; email: string; phone?: string; subject?: string; message: string }): Observable<void> {
    return this.http.post<void>(`${this.api}/website/contact`, body, { params: this.params() }).pipe(
      switchMap(() => of(void 0)),
    );
  }

  submitNewsletter(email: string): Observable<void> {
    return this.http.post<void>(`${this.api}/website/newsletter`, { email }, { params: this.params() }).pipe(
      switchMap(() => of(void 0)),
    );
  }

  submitServiceRequest(payload: ServiceRequestPayload): Observable<{ code: string }> {
    return this.http.post<{ code: string }>(`${this.api}/website/service-requests`, payload, { params: this.params() });
  }

  /** Tracking needs the email the request was submitted with (the code alone is not enough). A wrong code/email pair is a 404, i.e. null. */
  trackRequest(code: string, email: string): Observable<TrackedRequest | null> {
    const params = { ...this.params(), email: email.trim() };
    return this.notFoundAsNull(
      this.http.get<TrackedRequest>(`${this.api}/website/service-requests/track/${encodeURIComponent(code.trim())}`, { params }));
  }
}
