import { Directive, ElementRef, Input, OnChanges, Renderer2, RendererStyleFlags2, SimpleChanges, inject } from '@angular/core';
import { ThemeSettings } from '../models/site.model';

// Branding colors are passed separately from the theme so owners can override its defaults without changing the theme.
@Directive({
  selector: '[appTheme]',
  standalone: true,
})
export class ThemeDirective implements OnChanges {
  @Input('appTheme') theme?: ThemeSettings;
  @Input() primaryOverride?: string;
  @Input() secondaryOverride?: string;

  private el = inject(ElementRef<HTMLElement>);
  private renderer = inject(Renderer2);

  ngOnChanges(_: SimpleChanges): void {
    const t = this.theme;
    if (!t) return;
    const primary = this.primaryOverride || t.primary;
    const secondary = this.secondaryOverride || t.secondary;
    // DashCase routes this through style.setProperty(); without it Renderer2 uses `el.style[k] = v`, which silently drops every --site-* custom property.
    const set = (k: string, v: string) =>
      this.renderer.setStyle(this.el.nativeElement, k, v, RendererStyleFlags2.DashCase);

    set('--site-primary', primary);
    set('--site-primary-rgb', hexToRgb(primary));
    set('--site-secondary', secondary);
    set('--site-secondary-rgb', hexToRgb(secondary));
    set('--site-gradient', t.gradient);
    set('--site-font', t.font);
    set('--site-radius', t.radius + 'px');
    set('--site-spacing', (t.spacing || 1) + '');
    set('--site-btn-radius', t.buttonStyle === 'pill' ? '999px' : t.buttonStyle === 'square' ? '4px' : (t.radius * 0.7) + 'px');
    this.renderer.setStyle(this.el.nativeElement, 'font-family', t.font);
    // ngOnChanges runs again whenever the theme arrives or changes, so each pair has to be swapped,
    // not just added: adding alone left the wrapper carrying both theme-light and theme-dark.
    const pick = (cond: boolean, whenTrue: string, whenFalse: string) => {
      this.renderer.removeClass(this.el.nativeElement, cond ? whenFalse : whenTrue);
      this.renderer.addClass(this.el.nativeElement, cond ? whenTrue : whenFalse);
    };
    pick(!!t.darkMode, 'theme-dark', 'theme-light');
    pick(!!t.animations, 'theme-animate', 'theme-no-animate');
  }
}

function hexToRgb(hex: string): string {
  const h = hex.replace('#', '');
  const n = h.length === 3 ? h.split('').map((c) => c + c).join('') : h;
  const r = parseInt(n.slice(0, 2), 16);
  const g = parseInt(n.slice(2, 4), 16);
  const b = parseInt(n.slice(4, 6), 16);
  return `${r}, ${g}, ${b}`;
}
