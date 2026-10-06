import { Component, OnInit, ChangeDetectionStrategy, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Department, DepartmentRequest, Employee } from '../../models/hrm.model';
import { DepartmentService } from '../../services/department.service';
import { EmployeeService } from '../../services/employee.service';
import { Pagination } from '../../../../shared/components/pagination/pagination';
import { Loader } from '../../../../shared/components/loader/loader';
import { EmptyState } from '../../../../shared/components/empty-state/empty-state';
import { ConfirmDialog } from '../../../../shared/components/confirm-dialog/confirm-dialog';
import { HasPermissionDirective } from '../../../../shared/directives/has-permission.directive';

@Component({
  selector: 'app-departments',
  imports: [CommonModule, FormsModule, Pagination, Loader, EmptyState, ConfirmDialog, HasPermissionDirective],
  templateUrl: './departments.html',
  changeDetection: ChangeDetectionStrategy.OnPush,
  styleUrl: './departments.scss',
})
export class Departments implements OnInit {
  departments: Department[] = [];
  activeDepartments: Department[] = [];
  employees: Employee[] = [];
  totalPages = 0;
  page = 0;
  loading = false;
  saving = false;
  error = '';
  success = '';

  showForm = false;
  editingId: number | null = null;
  /** Row whose record is being re-read before the edit form opens; its edit button shows a spinner. */
  loadingEditId: number | null = null;
  form: DepartmentRequest = { name: '' };

  searchQuery = '';
  statusFilter: 'ALL' | 'ACTIVE' | 'INACTIVE' = 'ALL';

  deleteTarget: Department | null = null;

  constructor(
    private departmentService: DepartmentService,
    private employeeService: EmployeeService,
    private cdr: ChangeDetectorRef,
  ) {}

  ngOnInit(): void {
    this.load();
    this.employeeService.list(0, 1000, undefined, undefined, false).subscribe({
      next: (res) => {
        const inactiveStatuses = ['TERMINATED', 'RESIGNED', 'RETIRED', 'SUSPENDED'];
        this.employees = (res.content || []).filter(e => !inactiveStatuses.includes(e.employmentStatus as string));
        this.cdr.markForCheck();
      }
    });
  }

  get filteredDepartments(): Department[] {
    const q = this.searchQuery.trim().toLowerCase();
    return this.departments.filter(d => {
      const matchSearch = !q ||
        (d.name && d.name.toLowerCase().includes(q)) ||
        (d.code && d.code.toLowerCase().includes(q)) ||
        (d.id && d.id.toString().includes(q));
      
      const matchStatus = this.statusFilter === 'ALL' ||
        (this.statusFilter === 'ACTIVE' && d.active) ||
        (this.statusFilter === 'INACTIVE' && !d.active);

      return matchSearch && matchStatus;
    });
  }

  load(): void {
    this.loading = true;
    this.error = '';
    this.departmentService.list(this.page, 20).subscribe({
      next: (res) => {
        this.departments = res.content;
        this.totalPages = res.totalPages;
        this.loading = false;
        this.cdr.markForCheck();
      },
      error: () => {
        this.error = 'Failed to load departments';
        this.loading = false;
        this.cdr.markForCheck();
      },
    });
    this.departmentService.listActive().subscribe({ next: (d) => { this.activeDepartments = d; this.cdr.markForCheck(); } });
  }

  openCreate(): void {
    this.editingId = null;
    this.form = { name: '' };
    this.showForm = true;
  }

  /**
   * Re-reads the department before opening the form. It used to be filled from the list row, so anything
   * changed since this page loaded was silently written back over on save. Fetch-then-open, like
   * Invoices.openEdit, rather than opening from the row and replacing the form when the response lands,
   * which would overwrite what the user had already typed.
   */
  openEdit(dept: Department): void {
    if (this.loadingEditId !== null) return;
    this.loadingEditId = dept.id;
    this.error = '';
    this.cdr.markForCheck();
    this.departmentService.getById(dept.id).subscribe({
      next: (fresh) => {
        this.editingId = fresh.id;
        this.form = {
          name: fresh.name,
          code: fresh.code,
          description: fresh.description,
          headEmployeeId: fresh.headEmployeeId,
          parentDepartmentId: fresh.parentDepartmentId,
          budget: fresh.budget,
        };
        this.showForm = true;
        this.loadingEditId = null;
        this.cdr.markForCheck();
      },
      error: () => {
        this.loadingEditId = null;
        this.error = 'Could not load this department to edit. It may have been deleted - refresh the list.';
        this.cdr.markForCheck();
      },
    });
  }

  save(): void {
    this.saving = true;
    this.error = '';
    const payload: any = { ...this.form };
    Object.keys(payload).forEach((k) => {
      if (payload[k] === '' || payload[k] === null) delete payload[k];
    });
    const req = this.editingId
      ? this.departmentService.update(this.editingId, payload)
      : this.departmentService.create(payload);
    req.subscribe({
      next: () => {
        this.saving = false;
        this.showForm = false;
        this.success = this.editingId ? 'Department updated' : 'Department created';
        this.cdr.markForCheck();
        this.load();
      },
      error: (err) => {
        this.saving = false;
        this.error = err?.error?.message || 'Failed to save department';
        this.cdr.markForCheck();
      },
    });
  }

  toggle(dept: Department): void {
    this.departmentService.toggle(dept.id).subscribe({
      next: () => this.load(),
      error: () => { this.error = 'Failed to update department status'; this.cdr.markForCheck(); },
    });
  }

  confirmDelete(): void {
    if (!this.deleteTarget) return;
    this.departmentService.delete(this.deleteTarget.id).subscribe({
      next: () => {
        this.deleteTarget = null;
        this.success = 'Department deleted';
        this.cdr.markForCheck();
        this.load();
      },
      error: (err) => {
        this.error = err?.error?.message || 'Failed to delete department';
        this.deleteTarget = null;
        this.cdr.markForCheck();
      },
    });
  }

  goToPage(p: number): void {
    this.page = p;
    this.load();
  }

  // Rotating accent palette so each department card gets its own color.
  private cardPalette = ['#2563EB', '#6B46FF', '#16A34A', '#D97706', '#0EA5E9', '#DC2626', '#DB2777', '#0D9488'];
  cardColor(i: number): string {
    return this.cardPalette[i % this.cardPalette.length];
  }
}
