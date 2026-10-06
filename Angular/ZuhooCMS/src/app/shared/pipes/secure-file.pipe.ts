import { AsyncPipe } from '@angular/common';
import { ChangeDetectorRef, OnDestroy, Pipe, PipeTransform } from '@angular/core';
import { Observable } from 'rxjs';
import { SecureFileService } from '../services/secure-file.service';

/**
 * Async like AsyncPipe: private files (/api/files/..., legacy /uploads/...) resolve to short-lived signed URLs batched by SecureFileService; public and external URLs resolve immediately.
 * Emits null until a URL is ready, so no request is made for a half-resolved link.
 */
@Pipe({ name: 'secureFile', standalone: true, pure: false })
export class SecureFilePipe implements PipeTransform, OnDestroy {
  private readonly async: AsyncPipe;
  private lastInput: string | null | undefined = undefined;
  private source: Observable<string | null> | null = null;
  private initialised = false;

  constructor(cdr: ChangeDetectorRef, private files: SecureFileService) {
    this.async = new AsyncPipe(cdr);
  }

  transform(url: string | null | undefined): string | null {
    if (!this.initialised || url !== this.lastInput) {
      this.initialised = true;
      this.lastInput = url;
      this.source = this.files.resolve(url);
    }
    return this.async.transform(this.source) ?? null;
  }

  ngOnDestroy(): void {
    this.async.ngOnDestroy();
  }
}
