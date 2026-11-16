export interface AreaLookup {
  areaId: number;
  name: string;
  city: string;
}

export interface ComponentLookup {
  componentId: number;
  code: string;
  name: string;
  shelfLifeDays: number;
}

export interface UnitLookup {
  unitId: number;
  code: string;
  name: string;
}

export interface ResourceCategoryLookup {
  categoryId: number;
  name: string;
}

export interface ResourceTypeLookup {
  resourceTypeId: number;
  categoryId: number;
  categoryName: string;
  code: string;
  name: string;
  defaultUnitId: number;
  unitCode: string;
  trackingMode: 'Count' | 'Status' | 'Capacity';
}

export interface Lookups {
  areas: AreaLookup[];
  components: ComponentLookup[];
  units: UnitLookup[];
  resourceCategories: ResourceCategoryLookup[];
  resourceTypes: ResourceTypeLookup[];
  aboGroups: string[];
  rhFactors: string[];
  urgencies: string[];
  requestStatuses: string[];
  freshnessStatuses: string[];
}

export const EMPTY_LOOKUPS: Lookups = {
  areas: [],
  components: [],
  units: [],
  resourceCategories: [],
  resourceTypes: [],
  aboGroups: ['A', 'B', 'AB', 'O'],
  rhFactors: ['Positive', 'Negative'],
  urgencies: ['Routine', 'Urgent', 'Emergency'],
  requestStatuses: [
    'Submitted',
    'UnderReview',
    'Matched',
    'Contacted',
    'Fulfilled',
    'UnableToFulfil',
    'Closed',
    'Cancelled',
  ],
  freshnessStatuses: ['Fresh', 'Aging', 'Stale', 'Unknown', 'UnderReview'],
};
