import { Component, Input, Output, EventEmitter, ChangeDetectionStrategy, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Subject } from 'rxjs';
import { debounceTime, distinctUntilChanged, switchMap } from 'rxjs/operators';
import { RecruitmentSkillService } from '../../../modules/hrm/services/recruitment-skill.service';

const DEBOUNCE_MS = 250;

let instanceCount = 0;

/** Value stays the plain CSV string the backend expects, with no separate array model; suggestions come from RecruitmentSkillService but free text is still committed on Enter/comma. */
@Component({
  selector: 'app-skill-tag-input',
  imports: [CommonModule, FormsModule],
  templateUrl: './skill-tag-input.html',
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class SkillTagInput {
  @Input() label = 'Skills';
  @Input() placeholder = 'Type a skill and press Enter';
  @Input() value = '';
  @Output() valueChange = new EventEmitter<string>();

  draft = '';
  suggestions: string[] = [];
  showSuggestions = false;
  /** Ties the input to its suggestion list; unique per instance so two inputs can coexist. */
  readonly listId = `skill-tag-list-${++instanceCount}`;

  private query$ = new Subject<string>();

  constructor(private skillService: RecruitmentSkillService, private cdr: ChangeDetectorRef) {
    this.query$
      .pipe(
        debounceTime(DEBOUNCE_MS),
        distinctUntilChanged(),
        switchMap((q) => this.skillService.suggest(q)),
      )
      .subscribe((results) => {
        this.suggestions = results.filter((s) => !this.tags.includes(s));
        this.cdr.markForCheck();
      });
  }

  get tags(): string[] {
    return this.value ? this.value.split(',').map((s) => s.trim()).filter((s) => s.length > 0) : [];
  }

  onInput(): void {
    this.showSuggestions = true;
    this.query$.next(this.draft.trim());
  }

  onKeydown(event: KeyboardEvent): void {
    if (event.key === 'Enter' || event.key === ',') {
      event.preventDefault();
      this.commit(this.draft);
    } else if (event.key === 'Backspace' && !this.draft && this.tags.length) {
      this.removeTag(this.tags[this.tags.length - 1]);
    } else if (event.key === 'ArrowDown' && this.showSuggestions && this.suggestions.length) {
      // Walk into the suggestion list, which previously only a mouse could reach.
      event.preventDefault();
      this.focusOption(event.target as HTMLElement, 0);
    } else if (event.key === 'Escape' && this.showSuggestions) {
      event.preventDefault();
      // Only the list closes; the dialog around it stays open.
      event.stopPropagation();
      this.showSuggestions = false;
    }
  }

  onSuggestionKeydown(event: KeyboardEvent, skill: string): void {
    const button = event.target as HTMLElement;
    const options = this.optionsOf(button);
    const index = options.indexOf(button);

    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      this.commit(skill);
      this.focusInput(button);
    } else if (event.key === 'ArrowDown') {
      event.preventDefault();
      options[Math.min(index + 1, options.length - 1)]?.focus();
    } else if (event.key === 'ArrowUp') {
      event.preventDefault();
      if (index <= 0) this.focusInput(button);
      else options[index - 1].focus();
    } else if (event.key === 'Escape') {
      event.preventDefault();
      event.stopPropagation();
      this.showSuggestions = false;
      this.focusInput(button);
    }
  }

  private optionsOf(from: HTMLElement): HTMLElement[] {
    const list = from.closest('.skill-tag-suggestions');
    return list ? Array.from(list.querySelectorAll<HTMLElement>('[role="option"]')) : [];
  }

  private focusOption(from: HTMLElement, index: number): void {
    const root = from.closest('.position-relative');
    const options = root ? Array.from(root.querySelectorAll<HTMLElement>('[role="option"]')) : [];
    options[index]?.focus();
  }

  private focusInput(from: HTMLElement): void {
    from.closest('.position-relative')?.querySelector<HTMLElement>('input[role="combobox"]')?.focus();
  }

  selectSuggestion(skill: string): void {
    this.commit(skill);
  }

  commit(raw: string): void {
    const skill = raw.trim().replace(/,+$/, '');
    if (!skill) return;
    if (!this.tags.some((t) => t.toLowerCase() === skill.toLowerCase())) {
      this.emit([...this.tags, skill]);
    }
    this.draft = '';
    this.suggestions = [];
    this.showSuggestions = false;
  }

  removeTag(skill: string): void {
    this.emit(this.tags.filter((t) => t !== skill));
  }

  onBlur(event?: FocusEvent): void {
    // Focus moving into the suggestion list is not leaving the control, so the list
    // must not close under a keyboard user on its way in.
    const next = event?.relatedTarget;
    if (next instanceof HTMLElement && next.closest('.skill-tag-suggestions')) return;
    if (next instanceof HTMLElement && next.matches('input[role="combobox"]')) return;

    // Small delay so a suggestion click registers before the list hides.
    setTimeout(() => {
      this.showSuggestions = false;
      this.cdr.markForCheck();
    }, 150);
  }

  private emit(tags: string[]): void {
    this.value = tags.join(', ');
    this.valueChange.emit(this.value);
  }
}
