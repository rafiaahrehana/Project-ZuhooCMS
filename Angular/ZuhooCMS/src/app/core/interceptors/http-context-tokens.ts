import { HttpContextToken } from '@angular/common/http';

// Set true on a request whose caller renders its own inline error, so the failure is not reported twice.
export const SKIP_ERROR_TOAST = new HttpContextToken<boolean>(() => false);
