import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';
import { ApiService } from '../../core/services/api.service';

/** The server decides visibility from this: AVATAR/LOGO/WEBSITE are public, everything else is private and must be shown through the secureFile pipe. */
export type FilePurpose =
  | 'AVATAR' | 'LOGO' | 'WEBSITE'
  | 'ATTACHMENT' | 'RECEIPT' | 'STATEMENT' | 'DOCUMENT' | 'RESUME';

export interface FileUploadResult {
  fileName: string;
  /** Relative: /api/files/{id} (private) or /api/public/files/{id} (public). */
  fileUrl: string;
  fileId?: number;
  message: string;
}

@Injectable({ providedIn: 'root' })
export class FileUploadService {
  constructor(private api: ApiService) {}

  upload(file: File, purpose?: FilePurpose): Observable<FileUploadResult> {
    const formData = new FormData();
    formData.append('file', file);
    if (purpose) formData.append('purpose', purpose);
    return this.api.post<FileUploadResult>('/upload', formData);
  }

  // Images only, validated server-side against real image content, 5MB cap. Public.
  uploadAvatar(file: File): Observable<FileUploadResult> {
    const formData = new FormData();
    formData.append('file', file);
    return this.api.post<FileUploadResult>('/upload/avatar', formData);
  }
}
