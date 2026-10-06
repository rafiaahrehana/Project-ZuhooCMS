import { Component, OnInit, ChangeDetectionStrategy, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import {
  FORM_FIELD_TYPES,
  FormFieldType,
  ServiceCategory,
  ServiceTemplate,
  ServiceTemplateRequest,
  TemplateFormField,
  TemplateRequiredDocument,
  TemplateWorkflowStage,
} from '../../models/servicedesk.model';
import { ServiceTemplateService } from '../../services/service-template.service';
import { ServiceCategoryService } from '../../services/service-category.service';
import { Pagination } from '../../../../shared/components/pagination/pagination';
import { Loader } from '../../../../shared/components/loader/loader';
import { EmptyState } from '../../../../shared/components/empty-state/empty-state';
import { ConfirmDialog } from '../../../../shared/components/confirm-dialog/confirm-dialog';
import { HasPermissionDirective } from '../../../../shared/directives/has-permission.directive';
import { HasRoleDirective } from '../../../../shared/directives/has-role.directive';

import { BosCurrencyPipe } from '../../../../shared/pipes/bos-currency.pipe';
type EditorTab = 'basics' | 'fields' | 'documents' | 'stages';

@Component({
  selector: 'app-service-templates',
  imports: [BosCurrencyPipe, CommonModule, FormsModule, Pagination, Loader, EmptyState, ConfirmDialog, HasPermissionDirective, HasRoleDirective],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './templates.html',
})
export class Templates implements OnInit {
  templates: ServiceTemplate[] = [];
  categories: ServiceCategory[] = [];
  totalPages = 0;
  page = 0;
  loading = false;
  error = '';
  success = '';

  editorOpen = false;
  editorTab: EditorTab = 'basics';
  editingId: number | null = null;
  form: ServiceTemplateRequest = { name: '' };

  deleteTarget: ServiceTemplate | null = null;

  fieldTypes: FormFieldType[] = FORM_FIELD_TYPES;

  constructor(
    private templateService: ServiceTemplateService,
    private categoryService: ServiceCategoryService,
    private cdr: ChangeDetectorRef,
  ) {}

  ngOnInit(): void { this.load(); }

  load(): void {
    this.loading = true;
    this.error = '';
    this.cdr.markForCheck();
    this.templateService.list(this.page).subscribe({
      next: (res) => { this.templates = res.content; this.totalPages = res.totalPages; this.loading = false; this.cdr.markForCheck(); },
      error: () => { this.error = 'Failed to load templates'; this.loading = false; this.cdr.markForCheck(); }
    });
  }

  loadCategories(): void {
    if (this.categories.length) return;
    this.categoryService.lookup().subscribe({ next: (res) => { this.categories = res; this.cdr.markForCheck(); }, error: () => { this.categories = []; this.cdr.markForCheck(); } });
  }

  openCreate(): void {
    this.editingId = null;
    this.form = { name: '', active: true, formFields: [], requiredDocuments: [], workflowStages: [] };
    this.editorTab = 'basics';
    this.editorOpen = true;
    this.loadCategories();
  }

  // Fetches fresh so the nested data is present.
  openEdit(t: ServiceTemplate): void {
    this.editingId = t.id;
    this.templateService.getById(t.id).subscribe({
      next: (res) => {
        this.form = {
          name: res.name,
          description: res.description,
          categoryId: res.categoryId,
          defaultPrice: res.defaultPrice,
          estimatedDays: res.estimatedDays,
          iconUrl: res.iconUrl,
          active: res.active,
          formFields: res.formFields || [],
          requiredDocuments: res.requiredDocuments || [],
          workflowStages: res.workflowStages || [],
        };
        this.editorTab = 'basics';
        this.editorOpen = true;
        this.cdr.markForCheck();
        this.loadCategories();
      },
      error: () => { this.error = 'Failed to load template'; this.cdr.markForCheck(); }
    });
  }

  closeEditor(): void {
    this.editorOpen = false;
    this.editingId = null;
  }

  save(): void {
    const op = this.editingId
      ? this.templateService.update(this.editingId, this.form)
      : this.templateService.create(this.form);
    op.subscribe({
      next: () => {
        this.success = this.editingId ? 'Template updated' : 'Template created';
        this.closeEditor();
        this.cdr.markForCheck();
        this.load();
      },
      error: (err) => { this.error = err?.error?.message || 'Failed to save template'; this.cdr.markForCheck(); }
    });
  }

  addField(): void {
    const list = this.form.formFields || [];
    list.push({ label: '', fieldType: 'TEXT', required: false, sortOrder: list.length + 1 });
    this.form.formFields = list;
  }

  removeField(i: number): void {
    (this.form.formFields || []).splice(i, 1);
  }

  addDocument(): void {
    const list = this.form.requiredDocuments || [];
    list.push({ docName: '', mandatory: false, sortOrder: list.length + 1 });
    this.form.requiredDocuments = list;
  }

  removeDocument(i: number): void {
    (this.form.requiredDocuments || []).splice(i, 1);
  }

  addStage(): void {
    const list = this.form.workflowStages || [];
    list.push({ stageName: '', stageOrder: list.length + 1, requiresClientAction: false, requiresPayment: false, isFinalStage: false });
    this.form.workflowStages = list;
  }

  removeStage(i: number): void {
    (this.form.workflowStages || []).splice(i, 1);
  }

  doDelete(): void {
    if (!this.deleteTarget) return;
    this.templateService.delete(this.deleteTarget.id).subscribe({
      next: () => { this.deleteTarget = null; this.success = 'Template deleted'; this.cdr.markForCheck(); this.load(); },
      error: () => { this.deleteTarget = null; this.error = 'Cannot delete template'; this.cdr.markForCheck(); }
    });
  }

  goToPage(p: number): void { this.page = p; this.load(); }

  trackField(_: number, f: TemplateFormField): number | string { return f.id ?? f.label + _; }
  trackDoc(_: number, d: TemplateRequiredDocument): number | string { return d.id ?? d.docName + _; }
  trackStage(_: number, s: TemplateWorkflowStage): number | string { return s.id ?? s.stageName + _; }
}
