import { HttpErrorResponse } from '@angular/common/http';

/**
 * Backend error body (shared/exception/ApiResponse): { success, message, data, timestamp }.
 * On a bean-validation failure GlobalExceptionHandler.handleValidation puts the per-field map in `data`
 * and the message is the bare "Validation failed" - which on its own tells the user nothing about which
 * of twenty fields to fix. Composing the fields in here reaches every form at once, rather than making
 * each of ~60 components read error.data itself.
 */
interface ApiErrorBody {
  message?: unknown;
  error?: unknown;
  data?: unknown;
}

/** At most this many field errors are named; past that the toast stops being readable. */
const MAX_FIELDS = 4;

/**
 * Statuses whose body is empty or unreadable, where error.message is the raw
 * "Http failure response for http://...: 406 Not Acceptable" - a line no user can act on.
 */
const STATUS_SENTENCES: Record<number, string> = {
  // No body at all: GlobalExceptionHandler.frameworkError sends the status alone, because by definition
  // nothing it could write - a JSON error included - is acceptable to the caller.
  406: 'The server has no reply this page can read. Please reload the page and try again.',
  // Angular reports a request that never got a response (offline, DNS, CORS, server not running) as status 0.
  0: 'Could not reach the server. Check your connection and try again.',
  413: 'That file is too large to upload.',
  502: 'The server is not responding. Please try again in a moment.',
  503: 'The server is temporarily unavailable. Please try again in a moment.',
  504: 'The server took too long to respond. Please try again.',
};

/** Tries JSON.parse first because `responseType: 'text'` (ApiService.postText etc.) leaves error bodies as raw JSON text, making `error.error.message` undefined. */
export function extractErrorMessage(error: HttpErrorResponse, fallback = 'An error occurred'): string {
  if (error.error instanceof ErrorEvent) {
    return error.error.message || fallback;
  }

  // responseType: 'blob' (ApiService.getBlob - the PDF and spreadsheet downloads) hands back the error body
  // as a Blob, which cannot be read synchronously. readBlobErrorMessage() does that; here, say something
  // true about the status rather than printing "Http failure response ... 500 Internal Server Error".
  if (isBlobErrorBody(error)) {
    return STATUS_SENTENCES[error.status] || fallback;
  }

  const body = parseBody(error.error);
  if (body) {
    return compose(body, fallback, error);
  }

  if (typeof error.error === 'string' && error.error.trim()) {
    return error.error;
  }

  return STATUS_SENTENCES[error.status] || error.message || fallback;
}

/** True when the failed request asked for a Blob, so its error body is a Blob too. */
export function isBlobErrorBody(error: HttpErrorResponse): boolean {
  return typeof Blob !== 'undefined' && error.error instanceof Blob;
}

/**
 * The message from a Blob error body, read asynchronously. Used by the error interceptor so a failed
 * download reports what the server actually said; falls back to the synchronous text if it is not readable.
 */
export async function readBlobErrorMessage(error: HttpErrorResponse, fallback = 'An error occurred'): Promise<string> {
  if (!isBlobErrorBody(error)) return extractErrorMessage(error, fallback);
  try {
    const text = (await (error.error as Blob).text()).trim();
    if (!text) return STATUS_SENTENCES[error.status] || fallback;
    const body = parseBody(text);
    return body ? compose(body, fallback, error) : text;
  } catch {
    return extractErrorMessage(error, fallback);
  }
}

/** The error body as an object, whether it arrived parsed or as JSON text; null when it is neither. */
function parseBody(raw: unknown): ApiErrorBody | null {
  if (raw && typeof raw === 'object' && !(raw instanceof Blob)) return raw as ApiErrorBody;
  if (typeof raw === 'string' && raw.trim().startsWith('{')) {
    try {
      const parsed = JSON.parse(raw);
      return parsed && typeof parsed === 'object' ? parsed as ApiErrorBody : null;
    } catch {
      return null;
    }
  }
  return null;
}

function compose(body: ApiErrorBody, fallback: string, error: HttpErrorResponse): string {
  const message = asText(body.message) || asText(body.error);
  const fields = fieldErrors(body.data);

  if (!fields.length) {
    return message || STATUS_SENTENCES[error.status] || error.message || fallback;
  }

  const shown = fields.slice(0, MAX_FIELDS).join('; ');
  const extra = fields.length > MAX_FIELDS ? ` (and ${fields.length - MAX_FIELDS} more)` : '';
  // "Validation failed" adds nothing once the fields are listed, so it is dropped rather than prefixed.
  if (!message || /^validation (failed|error)\.?$/i.test(message)) {
    return `Please check these fields - ${shown}${extra}`;
  }
  return `${message.replace(/[.:]\s*$/, '')}: ${shown}${extra}`;
}

function asText(value: unknown): string {
  return typeof value === 'string' && value.trim() ? value.trim() : '';
}

/** The `data` map of a 400 turned into "Contact email: must be a well-formed email address" phrases. */
function fieldErrors(data: unknown): string[] {
  if (!data || typeof data !== 'object' || Array.isArray(data)) return [];
  return Object.entries(data as Record<string, unknown>)
    .filter(([, v]) => typeof v === 'string' && v.trim())
    .map(([field, v]) => `${label(field)}: ${String(v).trim().replace(/\.$/, '')}`);
}

/** 'contactEmail' -> 'Contact email'; 'items[0].qty' -> 'Items 1 qty'. Field names are wire names, not labels. */
function label(field: string): string {
  const words = field
    .replace(/\[(\d+)]/g, (_m, i: string) => ' ' + (Number(i) + 1))
    .replace(/\./g, ' ')
    .replace(/([a-z0-9])([A-Z])/g, '$1 $2')
    .replace(/[_-]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .toLowerCase();
  return words ? words.charAt(0).toUpperCase() + words.slice(1) : field;
}
