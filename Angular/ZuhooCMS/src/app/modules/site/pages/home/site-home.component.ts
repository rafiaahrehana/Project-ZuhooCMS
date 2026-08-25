import { Component, OnInit, inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import { NgClass } from '@angular/common';
import { SiteService } from '../../services/site.service';
import { SiteSettings, Stat, Service, Testimonial, BlogPost, PricingPlan, Faq } from '../../models/site.model';
import { DEFAULT_SITE } from '../../services/default-site.config';
import { SiteHeroComponent } from '../../components/hero/hero.component';
import { StatCardComponent } from '../../components/stat-card/stat-card.component';
import { ServiceCardComponent } from '../../components/service-card/service-card.component';
import { TestimonialCardComponent } from '../../components/testimonial-card/testimonial-card.component';
import { BlogCardComponent } from '../../components/blog-card/blog-card.component';
import { FaqItemComponent } from '../../components/faq-item/faq-item.component';
import { PricingCardComponent } from '../../components/pricing-card/pricing-card.component';

@Component({
  selector: 'app-site-home',
  standalone: true,
  imports: [RouterLink, NgClass, SiteHeroComponent, StatCardComponent, ServiceCardComponent, TestimonialCardComponent, BlogCardComponent, FaqItemComponent, PricingCardComponent],
  template: `
    <app-site-hero [settings]="settings"></app-site-hero>

    @if (stats.length) {
      <section class="band band-tight">
        <div class="container">
          <div class="row row-cols-2 row-cols-md-4 g-4">
            @for (s of stats; track $index) {
              <div class="col"><app-stat-card [stat]="s"></app-stat-card></div>
            }
          </div>
        </div>
      </section>
    }

    <section class="band">
      <div class="container">
        <div class="row g-5">
          <div class="col-lg-7">
            <h2 class="sec-title">About {{ settings?.companyName || 'us' }}</h2>
            <p class="body-copy mt-3">{{ settings?.aboutText }}</p>
            <dl class="mission-list mt-4 mb-0">
              @if (settings?.mission) {
                <div class="mission-item">
                  <dt>Mission</dt>
                  <dd>{{ settings!.mission }}</dd>
                </div>
              }
              @if (settings?.vision) {
                <div class="mission-item">
                  <dt>Vision</dt>
                  <dd>{{ settings!.vision }}</dd>
                </div>
              }
            </dl>
          </div>
          <div class="col-lg-5">
            @if (settings?.heroImageUrl) {
              <img [src]="settings!.heroImageUrl" class="about-img" [alt]="settings?.companyName || ''">
            }
          </div>
        </div>
      </div>
    </section>

    <section class="band band-muted">
      <div class="container">
        <h2 class="sec-title">What you can expect</h2>
        <div class="row g-0 mt-4 expect-list">
          @for (f of whatToExpect; track f.title) {
            <div class="col-md-6">
              <div class="expect-item">
                <i class="bi expect-icon" [ngClass]="f.icon"></i>
                <div>
                  <h3 class="expect-title">{{ f.title }}</h3>
                  <p class="expect-text mb-0">{{ f.text }}</p>
                </div>
              </div>
            </div>
          }
        </div>
      </div>
    </section>

    @if (services.length) {
      <section class="band">
        <div class="container">
          <div class="sec-head">
            <h2 class="sec-title">Services</h2>
            <a [routerLink]="basePath + '/services'" class="sec-link">All services</a>
          </div>
          <div class="row g-4 mt-1">
            @for (s of services.slice(0, 4); track s.id) {
              <div class="col-md-6 col-lg-3"><app-service-card [service]="s"></app-service-card></div>
            }
          </div>
        </div>
      </section>
    }

    <section class="band">
      <div class="container">
        <h2 class="sec-title">How it works</h2>
        <div class="row g-4 mt-1">
          @for (step of howWeWork; track step.title; let i = $index) {
            <div class="col-md-6 col-lg-3">
              <div class="step">
                <span class="step-num">Step {{ i + 1 }}</span>
                <h3 class="step-title">{{ step.title }}</h3>
                <p class="step-text mb-0">{{ step.text }}</p>
              </div>
            </div>
          }
        </div>
      </div>
    </section>

    @if (projects.length) {
      <section class="band">
        <div class="container">
          <div class="sec-head">
            <h2 class="sec-title">Recent work</h2>
            <a [routerLink]="basePath + '/portfolio'" class="sec-link">Full portfolio</a>
          </div>
          <div class="row g-4 mt-1">
            @for (p of projects.slice(0, 3); track p.id) {
              <div class="col-md-4">
                <article class="project h-100">
                  @if (p.coverImageUrl) {
                    <img [src]="p.coverImageUrl" class="project-img" [alt]="p.title">
                  }
                  <div class="project-body">
                    @if (p.category) { <span class="project-cat">{{ p.category }}</span> }
                    <h3 class="project-title">{{ p.title }}</h3>
                    <p class="body-copy small mb-0">{{ p.summary }}</p>
                  </div>
                </article>
              </div>
            }
          </div>
        </div>
      </section>
    }

    @if (pricing.length) {
      <section class="band">
        <div class="container">
          <h2 class="sec-title">Pricing</h2>
          <p class="sec-lede">Every job is quoted in writing before any work starts.</p>
          <div class="row g-4 mt-1 justify-content-center">
            @for (p of pricing.slice(0, 3); track p.id) {
              <div class="col-md-6 col-lg-4"><app-pricing-card [plan]="p"></app-pricing-card></div>
            }
          </div>
        </div>
      </section>
    }

    @if (testimonials.length) {
      <section class="band band-muted">
        <div class="container">
          <h2 class="sec-title">Clients</h2>
          <div class="row g-5 mt-1">
            @for (t of testimonials.slice(0, 3); track t.id) {
              <div class="col-md-6 col-lg-4"><app-testimonial-card [t]="t"></app-testimonial-card></div>
            }
          </div>
        </div>
      </section>
    }

    @if (blogs.length) {
      <section class="band">
        <div class="container">
          <div class="sec-head">
            <h2 class="sec-title">From the blog</h2>
            <a [routerLink]="basePath + '/blog'" class="sec-link">All posts</a>
          </div>
          <div class="row g-4 mt-1">
            @for (b of blogs.slice(0, 3); track b.id) {
              <div class="col-md-6 col-lg-4"><app-blog-card [post]="b"></app-blog-card></div>
            }
          </div>
        </div>
      </section>
    }

    @if (faqs.length) {
      <section class="band">
        <div class="container">
          <div class="row g-5">
            <div class="col-lg-4">
              <h2 class="sec-title">Questions</h2>
              <p class="sec-lede">Something we haven't covered here?
                <a [routerLink]="basePath + '/contact'" class="sec-link">Ask us directly</a>.
              </p>
            </div>
            <div class="col-lg-8">
              <div class="accordion" id="faqAccordion">
                @for (f of faqs.slice(0, 5); track f.id) {
                  <app-faq-item [faq]="f"></app-faq-item>
                }
              </div>
            </div>
          </div>
        </div>
      </section>
    }

    <section class="band">
      <div class="container">
        <div class="cta">
          <div>
            <h2 class="cta-title mb-2">Tell us what you need</h2>
            <p class="cta-text mb-0">Send through the details and you'll get back a scope, a timeline and a price.</p>
          </div>
          <div class="cta-actions">
            <a [routerLink]="basePath + '/request-service'" class="btn btn-light px-4 py-2"
               style="border-radius: var(--site-btn-radius)">Request a quote</a>
            <a [routerLink]="basePath + '/contact'" class="cta-link">Contact us</a>
          </div>
        </div>
      </div>
    </section>
  `,
  styles: [`
    /* House rules for this page: left-aligned headings in plain ink, hairline
       rules in place of drop shadows and hover lifts, and no decoration that
       isn't carrying information. Sections are told apart by whitespace and a
       single rule rather than by alternating gradient washes. */
    :host {
      --rule: rgba(20, 23, 26, 0.11);
      --ink-muted: #5c6570;
      display: block;
    }
    :host-context(.theme-dark) {
      --rule: rgba(255, 255, 255, 0.14);
      --ink-muted: rgba(255, 255, 255, 0.68);
    }

    .band { padding: 76px 0; }
    .band-tight { padding: 40px 0; }
    .band + .band { border-top: 1px solid var(--rule); }
    .band-muted { background: #f7f8f9; }
    .theme-dark .band-muted { background: rgba(255, 255, 255, 0.03); }

    .sec-title { font-size: clamp(1.5rem, 2.4vw, 1.95rem); font-weight: 600; letter-spacing: -0.015em; margin: 0; }
    .sec-head { display: flex; align-items: baseline; justify-content: space-between; gap: 1.5rem; flex-wrap: wrap; }
    .sec-lede { margin: 0.75rem 0 0; color: var(--ink-muted); max-width: 52ch; }
    .sec-link { color: var(--site-primary); text-decoration: none; font-weight: 500; font-size: 0.95rem; }
    .sec-link:hover { text-decoration: underline; }
    .sec-head .sec-link { white-space: nowrap; }

    .body-copy { color: var(--ink-muted); line-height: 1.68; max-width: 62ch; }

    /* Mission and vision are a definition list, which is what they are. The
       pair of gradient-icon tiles made them read as product features. */
    .mission-list { display: grid; gap: 1rem; }
    .mission-item { display: grid; grid-template-columns: 96px 1fr; gap: 1rem; padding-top: 1rem; border-top: 1px solid var(--rule); }
    .mission-item dt { font-size: 0.82rem; text-transform: uppercase; letter-spacing: 0.06em; color: var(--ink-muted); font-weight: 600; }
    .mission-item dd { margin: 0; color: var(--ink-muted); line-height: 1.6; }

    .about-img { width: 100%; max-height: 380px; object-fit: cover; border-radius: var(--site-radius); }

    .expect-list { border-top: 1px solid var(--rule); }
    .expect-item { display: flex; gap: 1rem; padding: 1.5rem 0; border-bottom: 1px solid var(--rule); height: 100%; }
    .expect-icon { color: var(--site-primary); font-size: 1.05rem; line-height: 1.6; flex: 0 0 auto; }
    .expect-title { font-size: 1.02rem; font-weight: 600; margin: 0 0 0.35rem; }
    .expect-text { color: var(--ink-muted); font-size: 0.94rem; line-height: 1.6; }
    @media (min-width: 768px) {
      .expect-list .col-md-6:nth-child(odd) .expect-item { padding-right: 2.5rem; margin-right: 2.5rem; border-right: 1px solid var(--rule); }
    }

    .step { padding-top: 0.9rem; border-top: 2px solid var(--site-primary); height: 100%; }
    .step-num { display: block; font-size: 0.78rem; font-weight: 600; letter-spacing: 0.07em; text-transform: uppercase; color: var(--site-primary); margin-bottom: 0.55rem; }
    .step-title { font-size: 1.02rem; font-weight: 600; margin: 0 0 0.35rem; }
    .step-text { color: var(--ink-muted); font-size: 0.94rem; line-height: 1.6; }

    .project { display: flex; flex-direction: column; border: 1px solid var(--rule); border-radius: var(--site-radius); overflow: hidden; }
    .project-img { width: 100%; height: 190px; object-fit: cover; }
    .project-body { padding: 1.25rem; }
    .project-cat { display: block; font-size: 0.78rem; text-transform: uppercase; letter-spacing: 0.06em; color: var(--ink-muted); margin-bottom: 0.4rem; }
    .project-title { font-size: 1.05rem; font-weight: 600; margin: 0 0 0.5rem; }

    .cta { display: flex; align-items: center; justify-content: space-between; gap: 2rem; flex-wrap: wrap; padding: 2.5rem; border-radius: var(--site-radius); background: var(--site-primary); color: #fff; }
    .cta-title { font-size: clamp(1.35rem, 2.2vw, 1.75rem); font-weight: 600; letter-spacing: -0.015em; }
    .cta-text { color: rgba(255, 255, 255, 0.82); max-width: 48ch; }
    .cta-actions { display: flex; align-items: center; gap: 1.5rem; }
    .cta-link { color: #fff; text-decoration: none; border-bottom: 1px solid rgba(255, 255, 255, 0.55); padding-bottom: 2px; white-space: nowrap; }
    .cta-link:hover { border-color: #fff; }

    @media (max-width: 767.98px) {
      .band { padding: 56px 0; }
      .mission-item { grid-template-columns: 1fr; gap: 0.35rem; }
      .cta { padding: 1.75rem; }
    }
  `]
})
export class SiteHomePage implements OnInit {
  private siteService = inject(SiteService);
  basePath = this.siteService.getBasePath();

  settings: SiteSettings = DEFAULT_SITE;
  stats: Stat[] = [];
  services: Service[] = [];
  testimonials: Testimonial[] = [];
  blogs: BlogPost[] = [];
  pricing: PricingPlan[] = [];
  faqs: Faq[] = [];
  projects: any[] = [];

  // Four concrete promises rather than six generic ones. The old six-up grid
  // ("Expert Team", "24/7 Support", "Proven Results") was copy that fits any
  // company on earth and therefore describes none of them.
  whatToExpect = [
    { icon: 'bi-person-check', title: 'One point of contact', text: 'The same person handles your account and answers when you call.' },
    { icon: 'bi-file-earmark-text', title: 'Priced before we start', text: 'You approve a written scope and a price before any work begins.' },
    { icon: 'bi-clock-history', title: 'Told where things stand', text: 'Progress and any delays reach you while there is still time to act on them.' },
    { icon: 'bi-lock', title: 'Your records stay yours', text: 'Documents and client data are kept confidential and never passed on.' },
  ];

  howWeWork = [
    { title: 'Talk it through', text: 'Tell us what you need. We ask questions until the scope is clear.' },
    { title: 'Written quote', text: 'Scope, timeline and price in writing, before you commit to anything.' },
    { title: 'The work', text: 'We get on with the job and keep you posted as it moves.' },
    { title: 'Handover', text: 'You get what was agreed, and someone to call afterwards.' },
  ];

  ngOnInit(): void {
    this.siteService.getSettings().subscribe(s => this.settings = s);
    this.siteService.getStats().subscribe(s => this.stats = s);
    this.siteService.getServices().subscribe(s => this.services = s);
    this.siteService.getTestimonials().subscribe(t => this.testimonials = t);
    this.siteService.getBlogs().subscribe(b => this.blogs = b);
    this.siteService.getPricing().subscribe(p => this.pricing = p);
    this.siteService.getFaqs().subscribe(f => this.faqs = f);
    this.siteService.getProjects().subscribe(p => this.projects = p);
  }
}
