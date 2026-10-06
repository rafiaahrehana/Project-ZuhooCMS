import { Injectable } from '@angular/core';
import { HttpClient, HttpContext, HttpParams } from '@angular/common/http';
import { Observable, map } from 'rxjs';
import { environment } from '../../../environments/environment';
 
export interface PagedResponse<T> {
  content: T[];
  totalElements: number;
  totalPages: number;
  currentPage: number;
  pageSize: number;
}
 
export interface ApiError {
  error: string;
  message: string;
  timestamp: string;
  status: number;
}
 
@Injectable({
  providedIn: 'root'
})
export class ApiService {
  private readonly baseUrl = environment.apiUrl;
 
  constructor(private http: HttpClient) {}
 
  get<T>(endpoint: string, params?: any, context?: HttpContext): Observable<T> {
    let httpParams = new HttpParams();
    if (params) {
      Object.keys(params).forEach(key => {
        if (params[key] !== null && params[key] !== undefined) {
          httpParams = httpParams.set(key, params[key]);
        }
      });
    }
    return this.http.get<T>(`${this.baseUrl}${endpoint}`, { params: httpParams, ...(context ? { context } : {}) });
  }
 
  post<T>(endpoint: string, data: any, context?: HttpContext): Observable<T> {
    return this.http.post<T>(`${this.baseUrl}${endpoint}`, data, context ? { context } : undefined);
  }
 
  put<T>(endpoint: string, data: any): Observable<T> {
    return this.http.put<T>(`${this.baseUrl}${endpoint}`, data);
  }
 
  patch<T>(endpoint: string, data: any): Observable<T> {
    return this.http.patch<T>(`${this.baseUrl}${endpoint}`, data);
  }
 
  delete<T>(endpoint: string): Observable<T> {
    return this.http.delete<T>(`${this.baseUrl}${endpoint}`);
  }

  /** Multipart POST under field name "file", for endpoints that process the upload themselves rather than the generic /upload store. */
  postFile<T>(endpoint: string, file: File): Observable<T> {
    const formData = new FormData();
    formData.append('file', file);
    return this.http.post<T>(`${this.baseUrl}${endpoint}`, formData);
  }

  uploadFile(file: File, purpose?: string): Observable<{ fileName: string; fileUrl: string; fileId?: number; message: string }> {
    const formData = new FormData();
    formData.append('file', file);
    // Decides visibility server-side (AVATAR/LOGO/WEBSITE public, the rest private).
    if (purpose) formData.append('purpose', purpose);
    return this.http.post<{ fileName: string; fileUrl: string; fileId?: number; message: string }>(
      `${this.baseUrl}/upload`, formData);
  }

  /** Text-response variants: endpoints returning text/plain would fail the default 'json' parse and turn a 200 into an error. */
  postText(endpoint: string, data: any): Observable<string> {
    return this.http.post(`${this.baseUrl}${endpoint}`, data, { responseType: 'text' });
  }

  patchText(endpoint: string, data: any): Observable<string> {
    return this.http.patch(`${this.baseUrl}${endpoint}`, data, { responseType: 'text' });
  }

  deleteText(endpoint: string): Observable<string> {
    return this.http.delete(`${this.baseUrl}${endpoint}`, { responseType: 'text' });
  }
 
  /** Binary GET (e.g. a generated PDF) for Blob-URL downloads rather than JSON parsing. */
  getBlob(endpoint: string): Observable<Blob> {
    return this.http.get(`${this.baseUrl}${endpoint}`, { responseType: 'blob' });
  }

  getPaged<T>(endpoint: string, page: number = 0, size: number = 20, params?: any): Observable<PagedResponse<T>> {
    const validPage = (typeof page === 'number' && !isNaN(page) && page >= 0) ? Math.floor(page) : 0;
    const validSize = (typeof size === 'number' && !isNaN(size) && size > 0) ? Math.floor(size) : 20;
    const httpParams = {
      page: validPage,
      size: validSize,
      ...params
    };
    // Spring Data's Page<T> JSON uses `number`/`size`, not `currentPage`/`pageSize`; normalized here so list screens see one shape.
    return this.get<any>(endpoint, httpParams).pipe(
      map((res: any): PagedResponse<T> => ({
        content: res?.content ?? [],
        totalElements: res?.totalElements ?? res?.page?.totalElements ?? 0,
        totalPages: res?.totalPages ?? res?.page?.totalPages ?? 0,
        currentPage: res?.currentPage ?? res?.number ?? res?.page?.number ?? page,
        pageSize: res?.pageSize ?? res?.size ?? res?.page?.size ?? size
      }))
    );
  }
}