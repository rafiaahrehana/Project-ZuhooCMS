import { Component, EventEmitter, Input, Output, ChangeDetectionStrategy, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FilePurpose, FileUploadResult, FileUploadService } from '../../services/file-upload.service';

// Mirrors what the server actually enforces: spring.servlet.multipart.max-file-size=10MB, and FilePurpose's per-purpose cap
// (AVATAR and LOGO 5MB, every other purpose 10MB). Kept in step with FilePurpose.java - a smaller number here rejects files
// the server would have accepted, a larger one lets the user wait for an upload the server throws away.
const SERVER_MAX_MB = 10;
const SERVER_PROFILE_IMAGE_MAX_MB = 5;
const PROFILE_IMAGE_PURPOSES = ['AVATAR', 'LOGO'];

const IMAGE_EXTENSIONS = ['.jpg', '.jpeg', '.png', '.gif', '.webp'];

@Component({
  selector: 'app-file-upload',
  imports: [CommonModule],
  templateUrl: './file-upload.html',
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class FileUpload {
  @Input() label = 'Upload File';
  @Input() accept = '';
  // 'avatar' hits the images-only /upload/avatar endpoint (5MB cap, content verified server-side); 'file' hits the general /upload endpoint.
  @Input() variant: 'file' | 'avatar' = 'file';
  // Client-side check for fast feedback only; the server enforces its own limit regardless. Left unset, the server's own cap
  // for this variant/purpose is used, so the default never rejects a file the server would have taken.
  @Input() maxSizeMB?: number;
  // Same image check as 'avatar' but still posts to the general /upload endpoint, for images that are not profile avatars.
  @Input() imagesOnly = false;
  // The server decides public vs private from this; ignored for variant='avatar' (always AVATAR), omitted means DOCUMENT (private).
  @Input() purpose?: FilePurpose | string;
  @Output() uploaded = new EventEmitter<FileUploadResult>();

  uploading = false;
  error = '';
  lastResult: FileUploadResult | null = null;

  constructor(private uploadService: FileUploadService, private cdr: ChangeDetectorRef) {}

  onFileSelected(event: Event): void {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!file) return;

    const validationError = this.validate(file);
    if (validationError) {
      this.error = validationError;
      this.lastResult = null;
      input.value = '';
      this.cdr.markForCheck();
      return;
    }

    this.uploading = true;
    this.error = '';
    this.cdr.markForCheck();
    const upload$ = this.variant === 'avatar'
      ? this.uploadService.uploadAvatar(file)
      : this.uploadService.upload(file, this.purpose as FilePurpose | undefined);
    upload$.subscribe({
      next: (result) => {
        this.uploading = false;
        this.lastResult = result;
        this.uploaded.emit(result);
        input.value = '';
        this.cdr.markForCheck();
      },
      error: (err) => {
        this.uploading = false;
        this.error = err?.error?.message || 'Upload failed';
        input.value = '';
        this.cdr.markForCheck();
      },
    });
  }

  /** The cap the server will apply to this upload: variant='avatar' always posts as AVATAR; otherwise the purpose decides. */
  private serverMaxMB(): number {
    const purpose = this.variant === 'avatar' ? 'AVATAR' : String(this.purpose ?? '').toUpperCase();
    return PROFILE_IMAGE_PURPOSES.includes(purpose) ? SERVER_PROFILE_IMAGE_MAX_MB : SERVER_MAX_MB;
  }

  // Fast feedback only; the server remains the real source of truth on extension, content-type and (for avatars) the decoded bytes.
  private validate(file: File): string | null {
    const serverMaxMB = this.serverMaxMB();
    const maxMB = Math.min(this.maxSizeMB || serverMaxMB, serverMaxMB);
    if (file.size > maxMB * 1024 * 1024) {
      return `File is too large. Maximum size is ${maxMB}MB`;
    }
    if (this.variant === 'avatar' || this.imagesOnly) {
      const name = file.name.toLowerCase();
      const hasImageExtension = IMAGE_EXTENSIONS.some((ext) => name.endsWith(ext));
      const isImageType = !file.type || file.type.startsWith('image/');
      if (!hasImageExtension || !isImageType) {
        return 'Please choose an image file (JPG, PNG, GIF, or WEBP)';
      }
    }
    return null;
  }
}
