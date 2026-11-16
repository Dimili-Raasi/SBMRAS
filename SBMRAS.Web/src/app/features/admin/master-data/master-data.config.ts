import { MasterDataType } from '../../../core/models/admin.models';

export type FieldKind = 'text' | 'code' | 'number' | 'textarea' | 'select';

export interface MasterField {
  key: string;
  label: string;
  kind: FieldKind;
  required?: boolean;
  maxLength?: number;
  min?: number;
  max?: number;
  pattern?: RegExp;
  patternHint?: string;
  /** For selects: static options or a master type whose active rows supply options. */
  options?: { value: string | number; label: string }[];
  optionsFrom?: MasterDataType;
  hint?: string;
  wide?: boolean;
}

export interface MasterColumn {
  key: string;
  label: string;
  mono?: boolean;
  num?: boolean;
}

export interface MasterTypeConfig {
  type: MasterDataType;
  label: string;
  singular: string;
  icon: string;
  columns: MasterColumn[];
  fields: MasterField[];
}

export const MASTER_TYPES: MasterTypeConfig[] = [
  {
    type: 'areas',
    label: 'Areas',
    singular: 'area',
    icon: 'map',
    columns: [
      { key: 'name', label: 'Name' },
      { key: 'city', label: 'City' },
      { key: 'state', label: 'State' },
      { key: 'pincode', label: 'PIN', mono: true },
    ],
    fields: [
      { key: 'name', label: 'Name', kind: 'text', required: true, maxLength: 100, wide: true },
      { key: 'city', label: 'City', kind: 'text', required: true, maxLength: 100 },
      { key: 'state', label: 'State', kind: 'text', required: true, maxLength: 100 },
      { key: 'pincode', label: 'PIN code', kind: 'code', maxLength: 6, pattern: /^[0-9]{6}$/, patternHint: 'Enter a 6-digit PIN code.' },
    ],
  },
  {
    type: 'components',
    label: 'Blood components',
    singular: 'blood component',
    icon: 'bloodtype',
    columns: [
      { key: 'code', label: 'Code', mono: true },
      { key: 'name', label: 'Name' },
      { key: 'shelfLifeDays', label: 'Shelf life (days)', num: true, mono: true },
      { key: 'storageNote', label: 'Storage note' },
    ],
    fields: [
      { key: 'code', label: 'Code', kind: 'code', required: true, maxLength: 10, pattern: /^[A-Za-z0-9_]+$/, patternHint: 'Letters, digits or underscore.' },
      { key: 'name', label: 'Name', kind: 'text', required: true, maxLength: 100 },
      { key: 'shelfLifeDays', label: 'Shelf life (days)', kind: 'number', required: true, min: 1, max: 3650 },
      { key: 'storageNote', label: 'Storage note', kind: 'textarea', maxLength: 400, wide: true },
    ],
  },
  {
    type: 'units',
    label: 'Units',
    singular: 'unit',
    icon: 'straighten',
    columns: [
      { key: 'code', label: 'Code', mono: true },
      { key: 'name', label: 'Name' },
    ],
    fields: [
      { key: 'code', label: 'Code', kind: 'code', required: true, maxLength: 10, pattern: /^[A-Za-z0-9_]+$/, patternHint: 'Letters, digits or underscore.' },
      { key: 'name', label: 'Name', kind: 'text', required: true, maxLength: 50 },
    ],
  },
  {
    type: 'resource-categories',
    label: 'Resource categories',
    singular: 'resource category',
    icon: 'category',
    columns: [
      { key: 'name', label: 'Name' },
      { key: 'description', label: 'Description' },
    ],
    fields: [
      { key: 'name', label: 'Name', kind: 'text', required: true, maxLength: 100, wide: true },
      { key: 'description', label: 'Description', kind: 'textarea', maxLength: 400, wide: true },
    ],
  },
  {
    type: 'resource-types',
    label: 'Medical resource types',
    singular: 'medical resource type',
    icon: 'medical_services',
    columns: [
      { key: 'code', label: 'Code', mono: true },
      { key: 'name', label: 'Name' },
      { key: 'categoryName', label: 'Category' },
      { key: 'unitCode', label: 'Default unit', mono: true },
      { key: 'trackingMode', label: 'Tracking' },
    ],
    fields: [
      { key: 'code', label: 'Code', kind: 'code', required: true, maxLength: 30, pattern: /^[A-Za-z0-9_]+$/, patternHint: 'Letters, digits or underscore.' },
      { key: 'name', label: 'Name', kind: 'text', required: true, maxLength: 100 },
      { key: 'categoryId', label: 'Category', kind: 'select', required: true, optionsFrom: 'resource-categories' },
      { key: 'defaultUnitId', label: 'Default unit', kind: 'select', required: true, optionsFrom: 'units' },
      {
        key: 'trackingMode',
        label: 'Tracking mode',
        kind: 'select',
        required: true,
        options: [
          { value: 'Count', label: 'Count (total / available)' },
          { value: 'Status', label: 'Status only' },
          { value: 'Capacity', label: 'Capacity' },
        ],
      },
    ],
  },
];
