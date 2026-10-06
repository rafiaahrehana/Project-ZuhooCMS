import { Injectable, OnDestroy } from '@angular/core';

/**
 * Ties the app's ~1040 form controls to the visible labels that already sit next to
 * them, and gives the icon-only buttons a name.
 *
 * Every field in this app is written the same way — a `<label class="form-label">` and
 * then the control, inside a column wrapper — but almost none of them carry `for`/`id`,
 * so a screen reader announces "edit text, blank" and a mouse click on the label does
 * nothing. Rather than hand-editing a thousand controls across 155 templates, this
 * walks the DOM and writes the real `for`/`id` pair, which fixes both at once: the name
 * is announced and clicking the label focuses the field, exactly as native HTML does.
 *
 * The matching rule is deliberately narrow: from a `<label>` with no `for`, take the
 * first control that follows it in document order, and give up the moment another
 * `<label>` appears first. That is correct for a row of label/field columns and for the
 * `form-check` shape where the label follows the checkbox, and it declines to guess
 * anywhere else.
 *
 * Nothing here changes layout, styling or text. Clicking a visible label now focuses
 * its field — a behaviour a sighted mouse user gains, and the only observable change.
 */
const CONTROL_SELECTOR = 'input,select,textarea';
const HIDDEN_INPUT = 'input[type="hidden"]';

/** The app's own wording for its icon buttons, taken from the `title`s it already uses. */
const ICON_NAMES: ReadonlyArray<readonly [string, string]> = [
  ['bi-pencil-square', 'Edit'],
  ['bi-pencil', 'Edit'],
  ['bi-trash', 'Delete'],
  ['bi-eye-slash', 'Hide password'],
  ['bi-eye', 'View'],
  ['bi-person-x', 'Remove person'],
  ['bi-x-circle-fill', 'Clear'],
  ['bi-x-circle', 'Clear'],
  ['bi-x-lg', 'Close'],
  ['bi-x', 'Close'],
  ['bi-plus-lg', 'Add'],
  ['bi-plus-circle', 'Add'],
  ['bi-plus', 'Add'],
  ['bi-chevron-left', 'Previous'],
  ['bi-chevron-right', 'Next'],
  ['bi-chevron-double-left', 'First'],
  ['bi-chevron-double-right', 'Last'],
  ['bi-chevron-up', 'Collapse'],
  ['bi-chevron-down', 'Expand'],
  ['bi-three-dots-vertical', 'More actions'],
  ['bi-three-dots', 'More actions'],
  ['bi-send', 'Send'],
  ['bi-download', 'Download'],
  ['bi-upload', 'Upload'],
  ['bi-printer', 'Print'],
  ['bi-search', 'Search'],
  ['bi-arrow-repeat', 'Refresh'],
  ['bi-arrow-clockwise', 'Refresh'],
  ['bi-funnel', 'Filter'],
  ['bi-gear', 'Settings'],
  ['bi-paperclip', 'Attach file'],
  ['bi-mic', 'Voice input'],
  ['bi-copy', 'Copy'],
  ['bi-clipboard', 'Copy'],
  ['bi-check-lg', 'Confirm'],
  ['bi-check2', 'Confirm'],
  ['bi-check', 'Confirm'],
  ['bi-bell', 'Notifications'],
  ['bi-list', 'Menu'],
  ['bi-star', 'Favourite'],
  ['bi-pin', 'Pin'],
];

let uid = 0;

/** `itemQty` / `item_qty` / `item-qty` all become "Item qty". */
function humanize(raw: string): string {
  const spaced = raw
    .replace(/[_-]+/g, ' ')
    .replace(/([a-z0-9])([A-Z])/g, '$1 $2')
    .replace(/\s+/g, ' ')
    .trim()
    .toLowerCase();
  return spaced.charAt(0).toUpperCase() + spaced.slice(1);
}

@Injectable({ providedIn: 'root' })
export class AccessibleNamesService implements OnDestroy {
  private observer: MutationObserver | null = null;
  private pending = false;

  constructor() {
    if (typeof document === 'undefined') return;

    this.scan(document.body);

    this.observer = new MutationObserver(() => this.schedule());
    this.observer.observe(document.body, { childList: true, subtree: true });
  }

  ngOnDestroy(): void {
    this.observer?.disconnect();
  }

  private schedule(): void {
    if (this.pending) return;
    this.pending = true;
    // A timer, not requestAnimationFrame: a background tab never paints, and a screen
    // reader in one would otherwise read a page of unlabelled fields.
    setTimeout(() => {
      this.pending = false;
      this.scan(document.body);
    });
  }

  /** Public so a check can be run from the console: `ng.getInjector(...)` is not needed for tests. */
  scan(root: ParentNode): void {
    this.associateLabels(root);
    this.nameButtons(root);
    this.nameOrphanControls(root);
  }

  // ---------------------------------------------------------------- labels

  private associateLabels(root: ParentNode): void {
    for (const label of Array.from(root.querySelectorAll<HTMLLabelElement>('label:not([for])'))) {
      // A label that wraps its control is already associated.
      if (label.querySelector(CONTROL_SELECTOR)) continue;
      if (!(label.textContent ?? '').trim()) continue;

      const control = this.findControlFor(label);
      if (!control) continue;
      if (this.hasName(control)) continue;

      if (!control.id) control.id = `a11y-field-${++uid}`;
      label.setAttribute('for', control.id);

      this.describeControl(control);
    }
  }

  /**
   * The control this label is for: the nearest one after it (or, for the `form-check`
   * shape, before it), stopping at any other label so a row of columns never
   * cross-associates.
   */
  private findControlFor(label: HTMLLabelElement): HTMLElement | null {
    let scope: HTMLElement | null = label.parentElement;
    for (let level = 0; scope && level < 3; level++, scope = scope.parentElement) {
      const nodes = Array.from(scope.querySelectorAll<HTMLElement>(`label,${CONTROL_SELECTOR}`));
      const index = nodes.indexOf(label);
      if (index === -1) continue;

      for (let i = index + 1; i < nodes.length; i++) {
        const node = nodes[i];
        if (node.tagName === 'LABEL') break;
        if (node.matches(HIDDEN_INPUT)) continue;
        return node;
      }
      for (let i = index - 1; i >= 0; i--) {
        const node = nodes[i];
        if (node.tagName === 'LABEL') break;
        if (node.matches(HIDDEN_INPUT)) continue;
        return node;
      }
    }
    return null;
  }

  /** Hooks up the hint or validation message that already sits under a field. */
  private describeControl(control: HTMLElement): void {
    if (control.hasAttribute('aria-describedby')) return;
    const wrapper = control.parentElement;
    if (!wrapper) return;

    const ids: string[] = [];
    for (const hint of Array.from(wrapper.querySelectorAll<HTMLElement>('.form-text,.invalid-feedback'))) {
      if (!(hint.textContent ?? '').trim()) continue;
      if (!hint.id) hint.id = `a11y-hint-${++uid}`;
      ids.push(hint.id);
    }
    if (ids.length) control.setAttribute('aria-describedby', ids.join(' '));
  }

  private hasName(control: HTMLElement): boolean {
    if (control.hasAttribute('aria-label') || control.hasAttribute('aria-labelledby')) return true;
    if (control.id && document.querySelector(`label[for="${CSS.escape(control.id)}"]`)) return true;
    if (control.closest('label')) return true;
    return false;
  }

  // ---------------------------------------------------------------- buttons

  private nameButtons(root: ParentNode): void {
    const candidates = Array.from(
      root.querySelectorAll<HTMLElement>('button,a[role="button"],[role="button"]'),
    );
    for (const button of candidates) {
      if (button.dataset['a11yChecked'] === '1') continue;
      button.dataset['a11yChecked'] = '1';

      if (button.hasAttribute('aria-label') || button.hasAttribute('aria-labelledby')) continue;
      if ((button.textContent ?? '').replace(/\s+/g, '').length) continue;

      const title = button.getAttribute('title');
      if (title && title.trim()) {
        // The app already says what this does on hover; say the same thing out loud.
        button.setAttribute('aria-label', title.trim());
        continue;
      }
      if (button.classList.contains('btn-close')) {
        button.setAttribute('aria-label', 'Close');
        continue;
      }
      // An eye next to a password box is not "view record"; it is the reveal toggle.
      if (this.isPasswordToggle(button)) {
        button.setAttribute('aria-label', 'Show or hide password');
        continue;
      }
      const name = this.nameFromIcon(button);
      if (name) button.setAttribute('aria-label', name);
    }
  }

  private isPasswordToggle(button: HTMLElement): boolean {
    // The reveal button sits next to its box in whatever wrapper the page happens to
    // use, so walk up a few levels rather than naming the wrappers.
    let scope: HTMLElement | null = button.parentElement;
    for (let level = 0; scope && level < 3; level++, scope = scope.parentElement) {
      if (scope.querySelector('input[type="password"],input[name*="assword"]')) return true;
    }
    return false;
  }

  private nameFromIcon(button: HTMLElement): string | null {
    const icon = button.querySelector('i,svg');
    if (!icon) return null;
    // `bi-send-fill` and `bi-send` are the same icon in two weights.
    const classes = (icon.getAttribute('class') ?? '').replace(/-(fill|lg)(?=\s|$)/g, '');
    for (const [token, name] of ICON_NAMES) {
      if (new RegExp(`(^|\\s)${token}(\\s|$)`).test(classes)) return name;
    }
    return null;
  }

  // ---------------------------------------------------------------- last resort

  /**
   * Controls with no visible label anywhere near them — the search and filter boxes in
   * the page toolbars. Their placeholder is the app's own wording for the field, so it
   * becomes the name; nothing visible changes.
   */
  private nameOrphanControls(root: ParentNode): void {
    for (const control of Array.from(root.querySelectorAll<HTMLElement>(CONTROL_SELECTOR))) {
      if (control.dataset['a11yNamed'] === '1') continue;
      if (control.matches(HIDDEN_INPUT)) continue;
      if (this.hasName(control)) {
        control.dataset['a11yNamed'] = '1';
        continue;
      }
      // Some toolbars caption a field with a styled <span class="…-label"> instead of a
      // real <label>. The caption is right there on screen; point the field at it.
      const caption = this.captionFor(control);
      if (caption) {
        if (!caption.id) caption.id = `a11y-caption-${++uid}`;
        control.setAttribute('aria-labelledby', caption.id);
        control.dataset['a11yNamed'] = '1';
        continue;
      }

      // A `title` is already the app's wording for the field; promote it to a real name,
      // since a tooltip is a weak and inconsistently announced fallback.
      const title = control.getAttribute('title');
      if (title && title.trim()) {
        control.setAttribute('aria-label', title.trim());
        control.dataset['a11yNamed'] = '1';
        continue;
      }

      const placeholder = control.getAttribute('placeholder');
      if (placeholder && placeholder.trim()) {
        control.setAttribute('aria-label', placeholder.trim().replace(/[.…]+$/, ''));
        control.dataset['a11yNamed'] = '1';
        continue;
      }
      if (control instanceof HTMLSelectElement) {
        // A filter select's first option is its own description ("All statuses",
        // "— Select method —"), which is the app's wording for what the select is for.
        const text = (control.options[0]?.textContent ?? '').replace(/\s+/g, ' ').trim();
        const cleaned = text.replace(/^[—\-–\s]+|[\s—\-–.…]+$/g, '').trim();
        if (cleaned) {
          control.setAttribute('aria-label', cleaned);
          control.dataset['a11yNamed'] = '1';
          continue;
        }
      }

      // A field in a table cell is named by its column, the way a sighted reader names it.
      const header = this.columnHeaderFor(control);
      if (header) {
        control.setAttribute('aria-label', header);
        control.dataset['a11yNamed'] = '1';
        continue;
      }

      // Last resort, so no reachable field is announced as a blank edit box: the form
      // field's own name, spelled out.
      const fieldName = control.getAttribute('name') ?? control.getAttribute('formcontrolname');
      if (fieldName) {
        control.setAttribute('aria-label', humanize(fieldName));
        control.dataset['a11yNamed'] = '1';
      }
    }
  }

  /** A caption element beside the control whose class says it is acting as a label. */
  private captionFor(control: HTMLElement): HTMLElement | null {
    const wrapper = control.parentElement;
    if (!wrapper) return null;
    for (const candidate of Array.from(wrapper.children)) {
      if (!(candidate instanceof HTMLElement) || candidate === control) continue;
      if (!/(^|[\s-])label([\s-]|$)/i.test(candidate.className)) continue;
      const text = (candidate.textContent ?? '').replace(/\s+/g, ' ').trim();
      if (text && text.length <= 60) return candidate;
    }
    return null;
  }

  /** The `<th>` above this control's cell, when it sits in a table row. */
  private columnHeaderFor(control: HTMLElement): string | null {
    const cell = control.closest('td,th');
    const row = cell?.parentElement;
    const table = cell?.closest('table');
    if (!cell || !row || !table) return null;

    const index = Array.prototype.indexOf.call(row.children, cell);
    const headerRow = table.tHead?.rows[0];
    const header = headerRow?.cells[index];
    const text = (header?.textContent ?? '').replace(/\s+/g, ' ').trim();
    return text || null;
  }
}
