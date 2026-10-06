import { Component, OnInit, ChangeDetectionStrategy, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ApiService, PagedResponse } from '../../../../core/services/api.service';
import { Loader } from '../../../../shared/components/loader/loader';
import { EmptyState } from '../../../../shared/components/empty-state/empty-state';
import { Pagination } from '../../../../shared/components/pagination/pagination';

@Component({
  selector: 'app-assignments',
  imports: [CommonModule, FormsModule, Loader, EmptyState, Pagination],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './assignments.html',
})
export class Assignments implements OnInit {
  assignments: any[] = [];
  totalPages = 0;
  page = 0;
  loading = false;
  error = '';

  constructor(private api: ApiService, private cdr: ChangeDetectorRef) {}

  ngOnInit(): void {
    this.load();
  }

  load(): void {
    this.loading = true;
    this.cdr.markForCheck();
    // ApiService already prepends environment.apiUrl (which contains "/api"), so repeating "/api" here 404s every call to "/api/hr/asset-history".
    this.api.getPaged<any>('/hr/asset-history', this.page, 20).subscribe({
      next: (res) => {
        this.assignments = res.content;
        this.totalPages = res.totalPages;
        this.loading = false;
        this.cdr.markForCheck();
      },
      error: () => {
        this.error = 'Failed to load assignments';
        this.loading = false;
        this.cdr.markForCheck();
      },
    });
  }

  goToPage(p: number): void {
    this.page = p;
    this.load();
  }
}
