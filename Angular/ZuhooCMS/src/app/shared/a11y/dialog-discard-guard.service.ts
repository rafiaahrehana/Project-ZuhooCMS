import {
  ApplicationRef,
  ComponentRef,
  EnvironmentInjector,
  Injectable,
  OnDestroy,
  createComponent,
  inject,
} from '@angular/core';
import { ConfirmDialog } from '../components/confirm-dialog/confirm-dialog';

/**
 * Asks before a part-filled dialog is thrown away.
 *
 * All 115 hand-rolled modals in this app dismiss the same way: the header's `.btn-close`, a footer Cancel,
 * or Escape - which DialogA11yService routes through the dialog's own close control precisely so that the
 * keyboard can never take a path the mouse does not. Every one of them dropped whatever had been typed with
 * no warning.
 *
 * Like DialogA11yService, this is one document-wide observer plus one document-wide click listener rather
 * than 115 template edits, and for the same reason: the dialogs are uniform, so the behaviour can be added
 * once. Nothing here changes any template, any component or any layout.
 *
 * How it works:
 *   - a `.modal.d-block` appearing in the DOM is tracked, and a baseline value is recorded for each of its
 *     form controls (at open, and for a control that appears later, the first time it takes focus);
 *   - a *trusted* `input`/`change` inside it marks that control as one the user actually operated;
 *   - a click on that dialog's close control is intercepted in the capture phase - so the template's own
 *     `(click)` never runs - and, only if the dialog is dirty, replaced by the app's ConfirmDialog. Confirming
 *     re-issues the very same click, so the dialog closes down its own code path; cancelling does nothing at
 *     all, which is why the typed data is necessarily still there.
 *
 * "Dirty" means: at least one control the user operated now holds a different value than its baseline. It is
 * deliberately not "a control was touched", so tabbing through a form, re-picking the option that was already
 * selected, or typing something and undoing it all close without a prompt - a confirmation on every dismissal
 * would be worse than the bug.
 */
const MODAL_SELECTOR = '.modal.d-block';

const FIELD_SELECTOR = 'input,select,textarea,[contenteditable]:not([contenteditable="false"])';

/**
 * Footer labels that are taken to mean "close this dialog". Narrower than DialogA11yService's list on
 * purpose: that list only needs to find *a* way out for Escape, whereas a wrong guess here would put a
 * discard prompt in front of a button that does not discard anything. "Back" in particular is a wizard step
 * in this app, not a dismissal.
 */
const CLOSE_TEXT = /^(cancel|close|dismiss)$/i;

/** Our own confirmation, which must never be guarded by itself. */
const OWN_CONFIRM_ATTR = 'data-discard-confirm';

interface TrackedDialog {
  el: HTMLElement;
  /** Value each control held when it was first seen, keyed by the control element. */
  baseline: Map<Element, string>;
  /** Controls that have had a trusted input/change - i.e. that the user actually operated. */
  operated: Set<Element>;
}

@Injectable({ providedIn: 'root' })
export class DialogDiscardGuardService implements OnDestroy {
  private appRef = inject(ApplicationRef);
  private envInjector = inject(EnvironmentInjector);

  private tracked: TrackedDialog[] = [];
  private observer: MutationObserver | null = null;
  private confirm: { ref: ComponentRef<ConfirmDialog>; host: HTMLElement } | null = null;
  /** Set while re-issuing the close click the user just confirmed, so it is not intercepted again. */
  private bypass = false;

  constructor() {
    if (typeof document === 'undefined') return;

    document.addEventListener('click', this.onClick, true);
    document.addEventListener('focusin', this.onFocusIn, true);
    document.addEventListener('input', this.onValueEvent, true);
    document.addEventListener('change', this.onValueEvent, true);

    this.observer = new MutationObserver((records) => this.onMutations(records));
    this.observer.observe(document.body, { childList: true, subtree: true });

    for (const el of Array.from(document.querySelectorAll<HTMLElement>(MODAL_SELECTOR))) this.track(el);
  }

  ngOnDestroy(): void {
    this.observer?.disconnect();
    document.removeEventListener('click', this.onClick, true);
    document.removeEventListener('focusin', this.onFocusIn, true);
    document.removeEventListener('input', this.onValueEvent, true);
    document.removeEventListener('change', this.onValueEvent, true);
  }

  // ---------------------------------------------------------------- tracking

  private onMutations(records: MutationRecord[]): void {
    for (const record of records) {
      for (const node of Array.from(record.removedNodes)) {
        if (!(node instanceof HTMLElement)) continue;
        for (const el of this.matchesIn(node)) {
          if (!el.isConnected) this.untrack(el);
        }
      }
      for (const node of Array.from(record.addedNodes)) {
        if (!(node instanceof HTMLElement)) continue;
        for (const el of this.matchesIn(node)) this.track(el);
      }
    }
  }

  private matchesIn(node: HTMLElement): HTMLElement[] {
    const found = Array.from(node.querySelectorAll<HTMLElement>(MODAL_SELECTOR));
    if (node.matches(MODAL_SELECTOR)) found.unshift(node);
    return found;
  }

  private track(el: HTMLElement): void {
    if (el.closest(`[${OWN_CONFIRM_ATTR}]`)) return;
    if (this.tracked.some((d) => d.el === el)) return;

    const dialog: TrackedDialog = { el, baseline: new Map(), operated: new Set() };
    this.tracked.push(dialog);

    // One turn later, the same way DialogA11yService waits before moving focus: the dialog's own bindings -
    // including the values an edit dialog is pre-filled with - are in place by then.
    setTimeout(() => {
      if (!el.isConnected) return;
      for (const field of Array.from(el.querySelectorAll(FIELD_SELECTOR))) {
        if (!dialog.baseline.has(field)) dialog.baseline.set(field, valueOf(field));
      }
    });
  }

  private untrack(el: HTMLElement): void {
    const index = this.tracked.findIndex((d) => d.el === el);
    if (index !== -1) this.tracked.splice(index, 1);
  }

  private dialogFor(target: EventTarget | null): TrackedDialog | null {
    if (!(target instanceof Node)) return null;
    const el = (target instanceof HTMLElement ? target : target.parentElement)?.closest<HTMLElement>(MODAL_SELECTOR);
    if (!el) return null;
    return this.tracked.find((d) => d.el === el) ?? null;
  }

  // ---------------------------------------------------------------- change detection

  /**
   * A control that appears after the dialog opened - a conditional row, a newly added line item - gets its
   * baseline here, before it can be typed into.
   */
  private onFocusIn = (event: Event): void => {
    const target = event.target;
    if (!(target instanceof Element) || !target.matches(FIELD_SELECTOR)) return;
    const dialog = this.dialogFor(target);
    if (!dialog) return;
    if (!dialog.baseline.has(target)) dialog.baseline.set(target, valueOf(target));
  };

  private onValueEvent = (event: Event): void => {
    // Untrusted events are Angular's or our own; only a real user edit counts. Note that `[(ngModel)]`
    // writing a value back does not dispatch input at all, so a programmatic fill can never mark a control
    // as operated.
    if (!event.isTrusted) return;
    const target = event.target;
    if (!(target instanceof Element) || !target.matches(FIELD_SELECTOR)) return;
    const dialog = this.dialogFor(target);
    if (!dialog) return;
    // Reached only if focusin somehow did not fire first; the empty string is the right baseline for a
    // control the user is typing into for the first time.
    if (!dialog.baseline.has(target)) dialog.baseline.set(target, '');
    dialog.operated.add(target);
  };

  private isDirty(dialog: TrackedDialog): boolean {
    for (const field of dialog.operated) {
      if (!field.isConnected) continue;
      if (valueOf(field) !== dialog.baseline.get(field)) return true;
    }
    return false;
  }

  // ---------------------------------------------------------------- interception

  private onClick = (event: MouseEvent): void => {
    if (this.bypass || this.confirm) return;

    const dialog = this.dialogFor(event.target);
    if (!dialog) return;

    const control = this.closeControlFor(dialog.el, event.target);
    if (!control) return;
    if (!this.isDirty(dialog)) return;

    // Capture phase on document, so the template's own (click) binding never sees this. The dialog therefore
    // stays open and keeps everything that was typed into it; nothing has to be restored afterwards.
    event.preventDefault();
    event.stopPropagation();
    event.stopImmediatePropagation();
    this.ask(control);
  };

  private closeControlFor(dialogEl: HTMLElement, target: EventTarget | null): HTMLElement | null {
    if (!(target instanceof Element)) return null;

    const closeButton = target.closest<HTMLElement>('.btn-close');
    if (closeButton && dialogEl.contains(closeButton)) return closeButton;

    const footerControl = target.closest<HTMLElement>('.modal-footer button,.modal-footer a');
    if (footerControl && dialogEl.contains(footerControl)) {
      const text = (footerControl.textContent ?? '').replace(/\s+/g, ' ').trim();
      if (CLOSE_TEXT.test(text)) return footerControl;
    }
    return null;
  }

  /**
   * The app's own ConfirmDialog, created rather than copied, so the discard prompt is the same component,
   * the same styling and the same two buttons as the 71 confirmations already in the app. DialogA11yService
   * picks it up like any other modal, which is what traps focus in it, makes Escape cancel it, and hands
   * focus back to the close control the user clicked when it goes away.
   */
  private ask(control: HTMLElement): void {
    const host = document.createElement('div');
    host.setAttribute(OWN_CONFIRM_ATTR, '');
    document.body.appendChild(host);

    const ref = createComponent(ConfirmDialog, { environmentInjector: this.envInjector, hostElement: host });
    ref.setInput('title', 'Discard Changes');
    ref.setInput('message', 'Close this form and discard your unsaved changes?');
    ref.setInput('confirmLabel', 'Discard');
    ref.setInput('danger', true);
    ref.setInput('visible', true);

    ref.instance.confirmed.subscribe(() => this.settle(control, true));
    ref.instance.cancelled.subscribe(() => this.settle(control, false));

    this.appRef.attachView(ref.hostView);
    ref.changeDetectorRef.detectChanges();
    this.confirm = { ref, host };
  }

  private settle(control: HTMLElement, discard: boolean): void {
    const open = this.confirm;
    if (!open) return;
    this.confirm = null;
    this.appRef.detachView(open.ref.hostView);
    open.ref.destroy();
    open.host.remove();

    if (!discard) return;
    // Re-issue exactly the click that was swallowed, so the dialog closes the way it always has - including
    // whatever else its Cancel handler does. `click()` is synchronous, so the flag covers only this call.
    this.bypass = true;
    try {
      control.click();
    } finally {
      this.bypass = false;
    }
  }
}

/** A comparable string for whatever kind of control this is. */
function valueOf(el: Element): string {
  if (el instanceof HTMLInputElement) {
    if (el.type === 'checkbox' || el.type === 'radio') return el.checked ? '1' : '0';
    if (el.type === 'file') return Array.from(el.files ?? []).map((f) => `${f.name}:${f.size}`).join('|');
    return el.value;
  }
  if (el instanceof HTMLTextAreaElement) return el.value;
  if (el instanceof HTMLSelectElement) return Array.from(el.selectedOptions).map((o) => o.value).join(',');
  if (el instanceof HTMLElement && el.isContentEditable) return el.innerHTML;
  return '';
}
