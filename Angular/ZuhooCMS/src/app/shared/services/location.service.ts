import { Injectable } from '@angular/core';
import { Observable, of } from 'rxjs';
import { HttpClient } from '@angular/common/http';
import { environment } from '../../../environments/environment';
import { globalHierarchyLabels, countryNames, GeoNodeDto } from '../models/location.model';

export interface CountryInfo {
  code: string;
  name: string;
}

@Injectable({
  providedIn: 'root'
})
export class LocationService {

  private apiUrl = environment.apiUrl + '/locations';

  constructor(private http: HttpClient) { }

  getCountriesMaster(): Observable<GeoNodeDto[]> {
    return this.http.get<GeoNodeDto[]>(`${this.apiUrl}/countries`);
  }

  // Country.id and Location.id are independent sequences that can collide, so top-level divisions must come from here, not getChildrenMaster.
  getDivisionsForCountry(countryId: number): Observable<GeoNodeDto[]> {
    return this.http.get<GeoNodeDto[]>(`${this.apiUrl}/countries/${countryId}/divisions`);
  }

  // Location-to-Location only (division -> district -> ... ). Do not pass a Country.id here.
  getChildrenMaster(parentId: number): Observable<GeoNodeDto[]> {
    return this.http.get<GeoNodeDto[]>(`${this.apiUrl}/children/${parentId}`);
  }

  getNode(id: number): Observable<GeoNodeDto> {
    return this.http.get<GeoNodeDto>(`${this.apiUrl}/${id}`);
  }

  createNode(request: any): Observable<GeoNodeDto> {
    return this.http.post<GeoNodeDto>(this.apiUrl, request);
  }

  updateNode(id: number, request: any): Observable<GeoNodeDto> {
    return this.http.put<GeoNodeDto>(`${this.apiUrl}/${id}`, request);
  }

  deleteNode(id: number): Observable<void> {
    return this.http.delete<void>(`${this.apiUrl}/${id}`);
  }

  /** Derived from globalHierarchyLabels' keys rather than GET /api/countries. */
  getAvailableCountries(): Observable<CountryInfo[]> {
    const countries = Object.keys(globalHierarchyLabels).map(code => ({
      code,
      name: countryNames[code] || code
    }));
    return of(countries);
  }
}
