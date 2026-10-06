import { SecureFilePipe } from '../../pipes/secure-file.pipe';
import {
  Component,
  Input,
  Output,
  EventEmitter,
  ElementRef,
  ViewChild,
  OnChanges,
  SimpleChanges,
  ChangeDetectionStrategy,
} from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';

export interface ChatMessage {
  id: number;
  authorId: number;
  authorName: string;
  content: string;
  createdAt: string;
  internal?: boolean;
  attachmentUrl?: string;
  attachmentFileName?: string;
}

/** Expects `messages` oldest-first; the backend's *OrderByCreatedAtDesc endpoints return newest-first, so callers must reverse before binding. */
@Component({
  selector: 'app-chat-thread',
  imports: [SecureFilePipe, CommonModule, FormsModule],
  templateUrl: './chat-thread.html',
  styleUrl: './chat-thread.scss',
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class ChatThread implements OnChanges {
  @Input() messages: ChatMessage[] = [];
  @Input() currentUserId: number | null = null;
  @Input() connected = false;
  @Input() sending = false;
  @Input() disabled = false;
  @Input() placeholder = 'Write a message...';
  @Input() emptyMessage = 'No messages yet — start the conversation.';
  // This component only picks and validates the file; uploading it and clearing pendingAttachmentName is the caller's job.
  @Input() allowAttachments = false;
  @Input() pendingAttachmentName: string | null = null;
  @Output() send = new EventEmitter<string>();
  @Output() attachFile = new EventEmitter<File>();
  @Output() removeAttachment = new EventEmitter<void>();

  @ViewChild('scrollAnchor') private scrollAnchor?: ElementRef<HTMLElement>;
  @ViewChild('fileInput') private fileInput?: ElementRef<HTMLInputElement>;

  draft = '';
  attachmentError = '';

  ngOnChanges(changes: SimpleChanges): void {
    if (changes['messages']) {
      // Wait a tick so the new bubble is actually in the DOM before scrolling to it.
      setTimeout(() => this.scrollToBottom(), 0);
    }
  }

  submit(): void {
    const text = this.draft.trim();
    if (!text || this.disabled) return;
    this.send.emit(text);
    this.draft = '';
  }

  openFilePicker(): void {
    this.attachmentError = '';
    this.fileInput?.nativeElement.click();
  }

  onFileSelected(event: Event): void {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    input.value = '';
    if (!file) return;

    const isImageType = !file.type || file.type.startsWith('image/');
    if (!isImageType) {
      this.attachmentError = 'Please choose an image file (JPG, PNG, GIF, or WEBP)';
      return;
    }
    this.attachmentError = '';
    this.attachFile.emit(file);
  }

  clearAttachment(): void {
    this.attachmentError = '';
    this.removeAttachment.emit();
  }

  isOwn(m: ChatMessage): boolean {
    return this.currentUserId != null && m.authorId === this.currentUserId;
  }

  isImageAttachment(m: ChatMessage): boolean {
    const url = m.attachmentUrl || '';
    return /\.(jpe?g|png|gif|webp)$/i.test(url);
  }

  initials(name: string): string {
    if (!name) return '?';
    const parts = name.trim().split(/\s+/);
    return ((parts[0]?.[0] || '') + (parts[1]?.[0] || '')).toUpperCase() || name[0]!.toUpperCase();
  }

  private scrollToBottom(): void {
    this.scrollAnchor?.nativeElement.scrollIntoView({ behavior: 'smooth', block: 'end' });
  }
}
