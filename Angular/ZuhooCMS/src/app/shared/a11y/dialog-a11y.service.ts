import { Injectable, OnDestroy } from '@angular/core';

/**
 * Gives every hand-rolled modal in the app real dialog semantics without touching
 * the 117 templates that render one.
 *
 * All of the app's dialogs are the same shape: a `<div class="modal d-block">` that
 * Angular inserts and removes with `@if`, wrapping `.modal-dialog > .modal-content`,
 * with the close control in `.modal-header .btn-close` and Cancel in `.modal-footer`.
 * Because the shape is uniform, one observer over the document can add what every one
 * of them is missing — role/aria-modal, an accessible name from the existing
 * `.modal-title`, focus moved in on open and restored on close, a Tab trap, Escape,
 * an inert background and a scroll lock — and no template needs to change.
 *
 * Escape deliberately does not close the dialog itself: it clicks the dialog's own
 * close control (the `.btn-close`, else the footer's Cancel/Close/Dismiss button), so
 * Escape can never take a different path than the mouse and can never skip a
 * confirmation that a Cancel click would show.
 *
 * Nothing here changes layout or styling. The one visual effect is that a focus ring
 * now lands on the dialog's first field when it opens.
 */
const MODAL_SELECTOR = '.modal.d-block';

const FOCUSABLE_SELECTOR = [
  'a[href]',
  'area[href]',
  'button:not([disabled])',
  'input:not([disabled]):not([type="hidden"])',
  'select:not([disabled])',
  'textarea:not([disabled])',
  'iframe',
  'summary',
  'audio[controls]',
  'video[controls]',
  '[contenteditable]:not([contenteditable="false"])',
  '[tabindex]:not([tabindex="-1"])',
].join(',');

/** Controls that count as "the first field" for initial focus. */
const FIELD_SELECTOR =
  'input:not([disabled]):not([readonly]):not([type="hidden"]),select:not([disabled]),textarea:not([disabled]):not([readonly])';

const CANCEL_TEXT = /^(cancel|close|dismiss|not now|no,? .*|back)$/i;

const LIVE_REGION_SELECTOR = '[aria-live],[role="alert"],[role="status"]';

interface OpenDialog {
  el: HTMLElement;
  /** What had focus when the dialog opened, so it can be handed back on close. */
  restoreTo: HTMLElement | null;
  /** Elements this dialog marked inert, to be un-marked in exactly the same set. */
  inerted: HTMLElement[];
}

let uid = 0;

@Injectable({ providedIn: 'root' })
export class DialogA11yService implements OnDestroy {
  private stack: OpenDialog[] = [];
  private observer: MutationObserver | null = null;
  /** Last element the pointer went down on, used when a dialog is opened from a non-focusable table row. */
  private lastPointerTarget: HTMLElement | null = null;
  private scrollLocked = false;
  private previousBodyOverflow = '';
  private previousBodyPaddingRight = '';

  constructor() {
    if (typeof document === 'undefined') return;

    document.addEventListener('pointerdown', this.onPointerDown, true);
    document.addEventListener('keydown', this.onKeyDown, true);

    this.observer = new MutationObserver((records) => this.onMutations(records));
    this.observer.observe(document.body, { childList: true, subtree: true });

    // Anything already in the DOM when the service starts.
    for (const el of Array.from(document.querySelectorAll<HTMLElement>(MODAL_SELECTOR))) {
      this.open(el);
    }
  }

  ngOnDestroy(): void {
    this.observer?.disconnect();
    document.removeEventListener('pointerdown', this.onPointerDown, true);
    document.removeEventListener('keydown', this.onKeyDown, true);
  }

  private onPointerDown = (event: Event): void => {
    const target = event.target;
    this.lastPointerTarget = target instanceof HTMLElement ? target : null;
  };

  private onMutations(records: MutationRecord[]): void {
    for (const record of records) {
      for (const node of Array.from(record.removedNodes)) {
        if (!(node instanceof HTMLElement)) continue;
        for (const el of this.matchesIn(node)) {
          if (!el.isConnected) this.close(el);
        }
      }
      for (const node of Array.from(record.addedNodes)) {
        if (!(node instanceof HTMLElement)) continue;
        for (const el of this.matchesIn(node)) this.open(el);
      }
    }
  }

  private matchesIn(node: HTMLElement): HTMLElement[] {
    const found = Array.from(node.querySelectorAll<HTMLElement>(MODAL_SELECTOR));
    if (node.matches(MODAL_SELECTOR)) found.unshift(node);
    return found;
  }

  // ---------------------------------------------------------------- open / close

  private open(el: HTMLElement): void {
    if (this.stack.some((d) => d.el === el)) return;

    el.setAttribute('role', 'dialog');
    el.setAttribute('aria-modal', 'true');
    if (!el.hasAttribute('tabindex')) el.setAttribute('tabindex', '-1');
    this.nameDialog(el);

    const restoreTo = this.resolveRestoreTarget();

    const dialog: OpenDialog = { el, restoreTo, inerted: [] };
    this.stack.push(dialog);

    // Only the topmost dialog holds the trap; the one below keeps its semantics but
    // its background stays inert under the new one.
    dialog.inerted = this.makeBackgroundInert(el);
    this.lockScroll();

    // One turn later, so the dialog's own content is in place first. A timer rather than
    // requestAnimationFrame, which a background tab never runs.
    setTimeout(() => {
      if (!el.isConnected) return;
      this.focusInitial(el);
    });
  }

  private close(el: HTMLElement): void {
    const index = this.stack.findIndex((d) => d.el === el);
    if (index === -1) return;
    const [dialog] = this.stack.splice(index, 1);

    for (const inert of dialog.inerted) inert.removeAttribute('inert');

    if (!this.stack.length) this.unlockScroll();

    const target = dialog.restoreTo;
    if (target && target.isConnected) {
      // A table row is not focusable on its own; make it focusable without making it
      // a tab stop so the caret can come back to where the dialog was opened from.
      if (!target.matches(FOCUSABLE_SELECTOR) && !target.hasAttribute('tabindex')) {
        target.setAttribute('tabindex', '-1');
      }
      try {
        target.focus({ preventScroll: false });
      } catch {
        /* element went away between the check and the call */
      }
    }
  }

  /**
   * Where focus should go when the dialog closes: whatever had focus at open time,
   * or — when the dialog was opened by clicking something unfocusable such as a
   * table row or a card — that row.
   */
  private resolveRestoreTarget(): HTMLElement | null {
    const active = document.activeElement;
    if (active instanceof HTMLElement && active !== document.body) return active;

    const pointer = this.lastPointerTarget;
    if (pointer && pointer.isConnected) {
      const row = pointer.closest<HTMLElement>('tr,[role="row"],button,a,[class*="-card"]');
      if (row) return row;
      return pointer;
    }
    return null;
  }

  // ---------------------------------------------------------------- naming

  private nameDialog(el: HTMLElement): void {
    if (el.hasAttribute('aria-labelledby') || el.hasAttribute('aria-label')) return;

    const title =
      el.querySelector<HTMLElement>('.modal-title') ??
      el.querySelector<HTMLElement>('.modal-header h1,.modal-header h2,.modal-header h3,.modal-header h4,.modal-header h5,.modal-header h6');

    let titleText = '';
    if (title) {
      if (!title.id) title.id = `a11y-dialog-title-${++uid}`;
      el.setAttribute('aria-labelledby', title.id);
      titleText = (title.textContent ?? '').replace(/\s+/g, ' ').trim();
    }

    // A dialog with no fields is a confirmation or a read-out; its body is safe to
    // announce as the description. A form's body is not — it would read the whole form.
    const body = el.querySelector<HTMLElement>('.modal-body');
    if (body && !el.querySelector(FIELD_SELECTOR) && !el.hasAttribute('aria-describedby')) {
      if (!body.id) body.id = `a11y-dialog-body-${++uid}`;
      el.setAttribute('aria-describedby', body.id);
    }

    // The close control: named for the dialog it closes, in the dialog's own words.
    for (const close of Array.from(el.querySelectorAll<HTMLElement>('.btn-close'))) {
      if (close.hasAttribute('aria-label') || close.hasAttribute('aria-labelledby')) continue;
      if ((close.textContent ?? '').trim()) continue;
      close.setAttribute('aria-label', titleText && titleText.length <= 48 ? `Close ${titleText}` : 'Close');
    }
  }

  // ---------------------------------------------------------------- focus

  private focusInitial(el: HTMLElement): void {
    const content = el.querySelector<HTMLElement>('.modal-content') ?? el;

    // The first field, per the app's own tab order — not the close button.
    const field = this.visible(Array.from(content.querySelectorAll<HTMLElement>(FIELD_SELECTOR)))[0];
    if (field) {
      field.focus();
      return;
    }

    // No fields: this is a confirmation or a read-out. Land on the footer's first
    // button, which in this app is always the safe one (Cancel / Dismiss / Close).
    const footerButton = this.visible(
      Array.from(content.querySelectorAll<HTMLElement>('.modal-footer button,.modal-footer a[href]')),
    )[0];
    if (footerButton) {
      footerButton.focus();
      return;
    }

    const anything = this.visible(Array.from(content.querySelectorAll<HTMLElement>(FOCUSABLE_SELECTOR)))[0];
    (anything ?? el).focus();
  }

  private visible(elements: HTMLElement[]): HTMLElement[] {
    return elements.filter((e) => e.offsetParent !== null || e.getClientRects().length > 0);
  }

  // ---------------------------------------------------------------- keyboard

  private onKeyDown = (event: KeyboardEvent): void => {
    const top = this.stack[this.stack.length - 1];
    if (!top || !top.el.isConnected) return;

    if (event.key === 'Escape') {
      const closer = this.findCloseControl(top.el);
      if (closer) {
        event.preventDefault();
        event.stopPropagation();
        // Go through the dialog's own close control, so Escape and the mouse always
        // take the same path — including any confirmation that path would show.
        closer.click();
      }
      return;
    }

    if (event.key !== 'Tab') return;

    const focusable = this.visible(Array.from(top.el.querySelectorAll<HTMLElement>(FOCUSABLE_SELECTOR)));
    if (!focusable.length) {
      event.preventDefault();
      top.el.focus();
      return;
    }
    const first = focusable[0];
    const last = focusable[focusable.length - 1];
    const active = document.activeElement as HTMLElement | null;

    if (active && !top.el.contains(active)) {
      event.preventDefault();
      (event.shiftKey ? last : first).focus();
      return;
    }
    if (event.shiftKey && active === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && active === last) {
      event.preventDefault();
      first.focus();
    }
  };

  private findCloseControl(el: HTMLElement): HTMLElement | null {
    const close = el.querySelector<HTMLElement>('.modal-header .btn-close,.btn-close');
    if (close) return close;

    for (const button of Array.from(el.querySelectorAll<HTMLElement>('.modal-footer button,.modal-footer a'))) {
      const text = (button.textContent ?? '').replace(/\s+/g, ' ').trim();
      if (CANCEL_TEXT.test(text)) return button;
    }
    return null;
  }

  // ---------------------------------------------------------------- background

  /**
   * Marks everything outside the dialog inert, walking up to `<body>` and inerting the
   * siblings on the way. Live regions are left alone: a save can fail while a dialog is
   * open and the toast is the only place that failure is reported.
   */
  private makeBackgroundInert(el: HTMLElement): HTMLElement[] {
    const inerted: HTMLElement[] = [];
    let node: HTMLElement | null = el;

    while (node && node.parentElement) {
      const parent: HTMLElement = node.parentElement;
      for (const sibling of Array.from(parent.children)) {
        if (!(sibling instanceof HTMLElement) || sibling === node) continue;
        this.inertExceptLiveRegions(sibling, inerted);
      }
      if (parent === document.body) break;
      node = parent;
    }
    return inerted;
  }

  /**
   * Marks `el` inert, unless it holds a live region — the toast container sits inside
   * `<app-root>`, so skipping any subtree that contains one would leave the whole app
   * live. Instead the walk goes around the live region and inerts everything beside it.
   */
  private inertExceptLiveRegions(el: HTMLElement, inerted: HTMLElement[]): void {
    if (el.hasAttribute('inert')) return;
    if (el.matches(LIVE_REGION_SELECTOR)) return;

    if (el.querySelector(LIVE_REGION_SELECTOR)) {
      for (const child of Array.from(el.children)) {
        if (child instanceof HTMLElement) this.inertExceptLiveRegions(child, inerted);
      }
      return;
    }
    el.setAttribute('inert', '');
    inerted.push(el);
  }

  // ---------------------------------------------------------------- scroll lock

  private lockScroll(): void {
    if (this.scrollLocked) return;
    const scrollbar = window.innerWidth - document.documentElement.clientWidth;
    this.previousBodyOverflow = document.body.style.overflow;
    this.previousBodyPaddingRight = document.body.style.paddingRight;
    document.body.style.overflow = 'hidden';
    if (scrollbar > 0) {
      // Pay back the width the scrollbar was taking, so nothing on the page shifts.
      const current = parseFloat(getComputedStyle(document.body).paddingRight) || 0;
      document.body.style.paddingRight = `${current + scrollbar}px`;
    }
    this.scrollLocked = true;
  }

  private unlockScroll(): void {
    if (!this.scrollLocked) return;
    document.body.style.overflow = this.previousBodyOverflow;
    document.body.style.paddingRight = this.previousBodyPaddingRight;
    this.scrollLocked = false;
  }
}
