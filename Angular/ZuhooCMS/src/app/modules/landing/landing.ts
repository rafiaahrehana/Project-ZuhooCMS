import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';

import { NavbarComponent } from './components/navbar/navbar';
import { HeroComponent } from './components/hero/hero';
import { WhyBusinessOsComponent } from './components/why-business-os/why-business-os';
import { ModulesComponent } from './components/modules/modules';
import { DashboardPreviewComponent } from './components/dashboard-preview/dashboard-preview';
import { PricingComponent } from './components/pricing/pricing';
import { FaqComponent } from './components/faq/faq';
import { CtaComponent } from './components/cta/cta';
import { FooterComponent } from './components/footer/footer';

@Component({
  selector: 'app-landing',
  standalone: true,
  imports: [
    CommonModule,
    NavbarComponent,
    HeroComponent,
    WhyBusinessOsComponent,
    ModulesComponent,
    DashboardPreviewComponent,
    PricingComponent,
    FaqComponent,
    CtaComponent,
    FooterComponent
  ],
  // Each accent-* class sets the --accent channel read by global.scss's "LANDING ACCENT SYSTEM"; custom properties cross Angular's view-encapsulation boundary, so recolouring happens only here.
  // No two neighbours share a hue family; `lime` is kept out of section washes and trusted-companies takes no accent, since its logos must keep third-party brand colours.
  template: `
    <div class="landing-wrapper">
      <app-navbar class="accent-emerald"></app-navbar>

      <!-- Charcoal-emerald skin: every band is dark, with emerald and teal alternating as the accent channel. -->
      <main>
        <app-hero class="accent-emerald"></app-hero>
        <app-dashboard-preview class="accent-teal"></app-dashboard-preview>
        <app-why-business-os class="accent-emerald"></app-why-business-os>
        <app-modules class="accent-teal"></app-modules>
        <app-pricing class="accent-emerald"></app-pricing>
        <app-faq class="accent-teal"></app-faq>
        <app-cta class="accent-emerald"></app-cta>
      </main>

      <app-footer class="accent-emerald"></app-footer>
    </div>
  `,
  styles: [`
    .landing-wrapper {
      scroll-behavior: smooth;
      overflow-x: hidden;
    }
  `]
})
export class Landing {
}
