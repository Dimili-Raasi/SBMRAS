import { IMPORT_TEMPLATES, ImportRowInput, InventoryKind } from '../../core/models/imports.models';

export const MAX_IMPORT_ROWS = 500;
const ABO = ['A', 'B', 'AB', 'O'];
const RH = ['Positive', 'Negative'];
const OP_STATUS = ['Available', 'Limited', 'Unavailable', 'Unknown'];

export interface ParsedImportRow extends ImportRowInput {
  localErrors: string[];
}

export interface ParsedCsv {
  rows: ParsedImportRow[];
  fileErrors: string[];
}

/** RFC-4180-ish CSV parser (quoted fields, escaped quotes, CRLF/LF). */
export function parseCsv(text: string): string[][] {
  const records: string[][] = [];
  let field = '';
  let record: string[] = [];
  let inQuotes = false;
  const src = text.replace(/^\uFEFF/, '');
  for (let i = 0; i < src.length; i++) {
    const ch = src[i];
    if (inQuotes) {
      if (ch === '"') {
        if (src[i + 1] === '"') {
          field += '"';
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field += ch;
      }
    } else if (ch === '"') {
      inQuotes = true;
    } else if (ch === ',') {
      record.push(field);
      field = '';
    } else if (ch === '\n' || ch === '\r') {
      if (ch === '\r' && src[i + 1] === '\n') {
        i++;
      }
      record.push(field);
      records.push(record);
      record = [];
      field = '';
    } else {
      field += ch;
    }
  }
  if (field !== '' || record.length) {
    record.push(field);
    records.push(record);
  }
  return records.filter((r) => r.some((v) => v.trim() !== ''));
}

function num(value: string, label: string, errors: string[]): number | null {
  if (!value) {
    return null;
  }
  const n = Number(value);
  if (!Number.isFinite(n)) {
    errors.push(`${label} must be a number.`);
    return null;
  }
  if (n < 0) {
    errors.push(`${label} cannot be negative.`);
  }
  return n;
}

function date(value: string, label: string, errors: string[]): string | null {
  if (!value) {
    return null;
  }
  if (Number.isNaN(Date.parse(value))) {
    errors.push(`${label} is not a valid date.`);
    return null;
  }
  return value;
}

function normalizeRh(value: string): string {
  const v = value.toLowerCase();
  if (v === '+' || v === 'pos' || v === 'positive') return 'Positive';
  if (v === '-' || v === 'neg' || v === 'negative') return 'Negative';
  return value;
}

/** Parses CSV text into contract import rows with light client-side checks (server validation is authoritative). */
export function toImportRows(text: string, kind: InventoryKind): ParsedCsv {
  const fileErrors: string[] = [];
  const records = parseCsv(text);
  if (!records.length) {
    return { rows: [], fileErrors: ['The file is empty.'] };
  }
  const header = records[0].map((h) => h.trim().toLowerCase());
  const missing = IMPORT_TEMPLATES[kind].filter((c) => !header.includes(c.toLowerCase()));
  if (missing.length) {
    fileErrors.push(`Missing column(s): ${missing.join(', ')}. Download the ${kind.toLowerCase()} template.`);
    return { rows: [], fileErrors };
  }
  const dataRecords = records.slice(1);
  if (!dataRecords.length) {
    fileErrors.push('The file has a header but no data rows.');
  }
  if (dataRecords.length > MAX_IMPORT_ROWS) {
    fileErrors.push(`The file has ${dataRecords.length} rows; the maximum per import is ${MAX_IMPORT_ROWS}.`);
  }
  const col = (r: string[], name: string) => (r[header.indexOf(name.toLowerCase())] ?? '').trim();

  const rows = dataRecords.slice(0, MAX_IMPORT_ROWS).map((r, index) => {
    const errors: string[] = [];
    const row: ParsedImportRow = {
      rowNumber: index + 1,
      rawData: r.join(',').slice(0, 1000),
      componentCode: null,
      aboGroup: null,
      rhFactor: null,
      resourceTypeCode: null,
      quantity: null,
      totalQuantity: null,
      availableQuantity: null,
      operationalStatus: null,
      earliestExpiryDate: null,
      validUntil: date(col(r, 'validUntil'), 'validUntil', errors),
      localErrors: errors,
    };
    if (kind === 'Blood') {
      row.componentCode = col(r, 'componentCode').toUpperCase() || null;
      row.aboGroup = col(r, 'aboGroup').toUpperCase() || null;
      row.rhFactor = col(r, 'rhFactor') ? normalizeRh(col(r, 'rhFactor')) : null;
      row.quantity = num(col(r, 'quantity'), 'quantity', errors);
      row.earliestExpiryDate = date(col(r, 'earliestExpiryDate'), 'earliestExpiryDate', errors);
      if (!row.componentCode) errors.push('componentCode is required.');
      if (!row.aboGroup) errors.push('aboGroup is required.');
      else if (!ABO.includes(row.aboGroup)) errors.push(`aboGroup must be one of ${ABO.join(', ')}.`);
      if (!row.rhFactor) errors.push('rhFactor is required.');
      else if (!RH.includes(row.rhFactor)) errors.push('rhFactor must be Positive or Negative.');
      if (!col(r, 'quantity')) errors.push('quantity is required.');
    } else {
      row.resourceTypeCode = col(r, 'resourceTypeCode').toUpperCase() || null;
      row.totalQuantity = num(col(r, 'totalQuantity'), 'totalQuantity', errors);
      row.availableQuantity = num(col(r, 'availableQuantity'), 'availableQuantity', errors);
      row.operationalStatus = col(r, 'operationalStatus') || null;
      if (!row.resourceTypeCode) errors.push('resourceTypeCode is required.');
      if (!col(r, 'totalQuantity')) errors.push('totalQuantity is required.');
      if (!col(r, 'availableQuantity')) errors.push('availableQuantity is required.');
      if (row.totalQuantity !== null && row.availableQuantity !== null && row.availableQuantity > row.totalQuantity) {
        errors.push('availableQuantity cannot exceed totalQuantity.');
      }
      if (row.operationalStatus && !OP_STATUS.includes(row.operationalStatus)) {
        errors.push(`operationalStatus must be one of ${OP_STATUS.join(', ')}.`);
      }
    }
    return row;
  });
  return { rows, fileErrors };
}

export function templateCsv(kind: InventoryKind): string {
  const header = IMPORT_TEMPLATES[kind].join(',');
  const examples =
    kind === 'Blood'
      ? ['PRBC,O,Positive,12,,', 'FFP,AB,Negative,4,,']
      : ['ICU_BED,10,4,Available,', 'O2_CYL,40,12,Limited,'];
  return [header, ...examples].join('\r\n') + '\r\n';
}

/** SHA-256 hex (64 chars) of the file text — the API uses it to reject re-importing the same file. */
export async function sha256Hex(text: string): Promise<string> {
  if (typeof crypto !== 'undefined' && crypto.subtle) {
    const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
    return Array.from(new Uint8Array(digest))
      .map((b) => b.toString(16).padStart(2, '0'))
      .join('');
  }
  // Non-secure context fallback: deterministic FNV-1a, padded to 64 hex chars.
  let h = 2166136261;
  for (let i = 0; i < text.length; i++) {
    h = Math.imul(h ^ text.charCodeAt(i), 16777619);
  }
  return (h >>> 0).toString(16).padStart(8, '0').repeat(8);
}

export function rowValuesLabel(row: {
  componentCode: string | null;
  aboGroup: string | null;
  rhFactor: string | null;
  resourceTypeCode: string | null;
}): string {
  if (row.resourceTypeCode) {
    return row.resourceTypeCode;
  }
  const rh = row.rhFactor === 'Positive' ? '+' : row.rhFactor === 'Negative' ? '−' : '';
  return [row.componentCode, row.aboGroup ? `${row.aboGroup}${rh}` : null].filter(Boolean).join(' ') || '—';
}

export function splitMessages(value: string | null | undefined): string[] {
  return (value ?? '')
    .split(/[|;\n]/)
    .map((s) => s.trim())
    .filter(Boolean);
}
