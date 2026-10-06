import { Component, EventEmitter, Input, Output, ChangeDetectionStrategy } from '@angular/core';
import { RouterLink } from '@angular/router';
import { DuplicateMatch } from '../../../modules/crm/models/crm.model';

// Non-blocking: the record already exists by the time this shows, so it offers only "view the existing one" or "dismiss", never an undo.
@Component({
  selector: 'app-duplicate-warning-modal',
  imports: [RouterLink],
  templateUrl: './duplicate-warning-modal.html',
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class DuplicateWarningModal {
  @Input() match: DuplicateMatch | null = null;
  @Output() dismissed = new EventEmitter<void>();

  matchedOnLabel(): string {
    const on = this.match?.matchedOn || '';
    return on.charAt(0).toUpperCase() + on.slice(1);
  }
}
