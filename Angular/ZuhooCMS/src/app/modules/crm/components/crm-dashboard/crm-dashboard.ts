import { Component, OnInit, ChangeDetectionStrategy, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
import { ApiService } from '../../../../core/services/api.service';
import { CrmDashboardSummary } from '../../models/crm.model';
import { StatCard } from '../../../../shared/components/stat-card/stat-card';
import { Loader } from '../../../../shared/components/loader/loader';
import { BosCurrencyPipe } from '../../../../shared/pipes/bos-currency.pipe';

// Deliberately separate from /dashboard, whose widget-registry framework is tied to one DashboardSummary DTO; charts live in Reports.
@Component({
  selector: 'app-crm-dashboard',
  imports: [CommonModule, RouterLink, StatCard, Loader, BosCurrencyPipe],
  templateUrl: './crm-dashboard.html',
  changeDetection: ChangeDetectionStrategy.OnPush,
  styleUrl: './crm-dashboard.scss',
})
export class CrmDashboard implements OnInit {
  summary?: CrmDashboardSummary;
  loading = false;
  error = '';

  constructor(private api: ApiService, private cdr: ChangeDetectorRef) {}

  ngOnInit(): void {
    this.load();
  }

  load(): void {
    this.loading = true;
    this.error = '';
    this.cdr.markForCheck();
    this.api.get<CrmDashboardSummary>('/crm/dashboard/summary').subscribe({
      next: (res) => {
        this.summary = res;
        this.loading = false;
        this.cdr.markForCheck();
      },
      error: () => {
        this.error = 'Failed to load CRM dashboard';
        this.loading = false;
        this.cdr.markForCheck();
      },
    });
  }
}
