// Shared definitions of the units map: states, their labels and the boxes
// where units are drawn.
import type { CollectionEntry } from 'astro:content';

export type Status = (typeof STATUSES)[number];

export type Unit = CollectionEntry<'units'>['data'];

export type Group = CollectionEntry<'groups'>['data'];

export const STATUSES = ['implemented', 'partial', 'absent', 'out'] as const;

export const STATUS_LABELS: Record<Status, string> = {
    implemented: 'Implementado',
    partial: 'Parcial',
    absent: 'No escopo, não implementado',
    out: 'Fora do escopo',
};

export const BOXES = [
    'entrypoint',
    'catalog-title',
    'catalog-main',
    'catalog-privacy',
    'catalog-guides',
    'lifecycle',
    'ginga-ncl',
    'ginga-html5',
    'core-transport',
    'core-media',
    'core-platform',
    'core-state',
    'webservices',
    'general',
] as const;

export const UNITS_DATA_PATH = 'aop-units.json';

// Widest a group can be, in grid columns (the widest grid of the map).
export const MAX_SPAN = 7;

// Orders units or groups by the first section of the standard they cite:
// numbered sections first, then the annexes, part by part.
export function bySections(a: { sections: string }, b: { sections: string }): number {
    const left = sectionKey(a.sections);
    const right = sectionKey(b.sections);
    const length = Math.min(left.length, right.length);
    for (let i = 0; i < length; i++) {
        const order = comparePart(left[i], right[i]);
        if (order !== 0) {
            return order;
        }
    }
    return left.length - right.length;
}

// Label of a unit inside a box: the id without the namespace of the box and,
// for a unit drawn under another, without the stem of its parent.
export function unitLabel(unit: Unit, prefix: string): string {
    if (unit.parent) {
        const stem = unit.parent.replace(/-manager$/, '');
        return unit.id.replace(`${stem}-`, '');
    }
    if (prefix !== '' && unit.id.startsWith(prefix)) {
        return unit.id.slice(prefix.length);
    }
    return unit.id;
}

function sectionKey(sections: string): (number | string)[] {
    const first = sections.split(/[,;]/)[0].trim();
    return first.split('.').map((part) => {
        const number = Number(part);
        return Number.isInteger(number) ? number : part;
    });
}

function comparePart(a: number | string, b: number | string): number {
    if (typeof a === 'number' && typeof b === 'number') {
        return a - b;
    }
    if (typeof a === 'number') {
        return -1;
    }
    if (typeof b === 'number') {
        return 1;
    }
    return a.localeCompare(b);
}
