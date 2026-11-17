// Interaction of the units map: detail panel on click and legend filter by
// status.
import type { Group, Status, Unit } from '../lib/aop-units';
import { STATUSES, STATUS_LABELS } from '../lib/aop-units';

type MapData = {
    units: Unit[];
    groups: Group[];
};

type Field = [string, Node];

async function initMap(root: HTMLElement): Promise<void> {
    const url = root.dataset.unitsUrl;
    if (!url) {
        throw new Error('units map: no data-units-url');
    }
    const response = await fetch(url);
    if (!response.ok) {
        throw new Error(`units data: HTTP ${response.status}`);
    }
    const data = (await response.json()) as MapData;
    const unitsById = new Map(data.units.map((unit) => [unit.id, unit]));
    const groupsById = new Map(data.groups.map((group) => [group.id, group]));
    const panel = detailPanel(root);

    root.addEventListener('click', (event) => {
        const target = closestControl(event.target, '[data-unit], [data-group], [data-filter], [data-member]');
        if (!target || !root.contains(target)) {
            return;
        }
        const { filter, unit, group, member } = target.dataset;
        if (filter) {
            toggleFilter(root, target, filter);
            return;
        }
        if (member) {
            showUnit(panel, requireEntry(unitsById, member));
            return;
        }
        selectElement(root, target);
        if (unit) {
            showUnit(panel, requireEntry(unitsById, unit));
            return;
        }
        if (group) {
            const entry = requireEntry(groupsById, group);
            const members = data.units.filter((item) => item.group === entry.id);
            showGroup(panel, entry, members);
        }
    });
}

function toggleFilter(root: HTMLElement, button: HTMLElement, status: string): void {
    const isActive = root.dataset.filter === status;
    root.querySelectorAll('.aop-legend-item').forEach((item) => {
        item.classList.remove('is-active');
    });
    if (isActive) {
        delete root.dataset.filter;
        return;
    }
    root.dataset.filter = status;
    button.classList.add('is-active');
}

function selectElement(root: HTMLElement, element: HTMLElement): void {
    root.querySelectorAll('.is-selected').forEach((item) => {
        item.classList.remove('is-selected');
    });
    element.classList.add('is-selected');
}

function showUnit(panel: HTMLElement, unit: Unit): void {
    const fields: Field[] = [
        ['Estado', statusBadge(unit.status)],
        ['Natureza', text(unit.nature)],
        ['Seções da norma', text(unit.sections)],
    ];
    if (unit.parent) {
        fields.push(['Parte de', code(unit.parent)]);
    }
    if (unit.group) {
        fields.push(['Grupo', code(unit.group)]);
    }
    if (unit.note) {
        fields.push(['Nota', text(unit.note)]);
    }
    panel.replaceChildren(heading(unit.id), fieldList(fields));
}

function showGroup(panel: HTMLElement, group: Group, members: Unit[]): void {
    const counts = STATUSES.map((status) => {
        const count = members.filter((unit) => unit.status === status).length;
        return `${STATUS_LABELS[status]}: ${count}`;
    }).join(' · ');
    const list = document.createElement('div');
    list.className = 'aop-detail-members';
    members.forEach((unit) => {
        const button = document.createElement('button');
        button.type = 'button';
        button.className = `aop-unit status-${unit.status}`;
        button.dataset.member = unit.id;
        button.textContent = unit.id;
        list.append(button);
    });
    const fields = fieldList([
        ['Unidades', text(String(members.length))],
        ['Por estado', text(counts)],
    ]);
    panel.replaceChildren(heading(group.label), fields, list);
}

function heading(value: string): HTMLElement {
    const element = document.createElement('p');
    element.className = 'aop-detail-id';
    element.textContent = value;
    return element;
}

function fieldList(fields: Field[]): HTMLElement {
    const list = document.createElement('dl');
    list.className = 'aop-detail-fields';
    fields.forEach(([label, value]) => {
        const term = document.createElement('dt');
        term.textContent = label;
        const description = document.createElement('dd');
        description.append(value);
        list.append(term, description);
    });
    return list;
}

function statusBadge(status: Status): HTMLElement {
    const element = document.createElement('span');
    element.className = `aop-detail-status status-${status}`;
    element.textContent = STATUS_LABELS[status];
    return element;
}

function code(value: string): HTMLElement {
    const element = document.createElement('code');
    element.textContent = value;
    return element;
}

function text(value: string): Text {
    return document.createTextNode(value);
}

function closestControl(target: EventTarget | null, selector: string): HTMLElement | null {
    if (!(target instanceof Element)) {
        return null;
    }
    return target.closest<HTMLElement>(selector);
}

function detailPanel(root: HTMLElement): HTMLElement {
    const panel = root.querySelector<HTMLElement>('.aop-detail');
    if (!panel) {
        throw new Error('units map: no detail panel');
    }
    return panel;
}

function requireEntry<T>(entries: Map<string, T>, id: string): T {
    const entry = entries.get(id);
    if (entry === undefined) {
        throw new Error(`units map: unknown id ${id}`);
    }
    return entry;
}

function reportFailure(root: HTMLElement, error: unknown): void {
    const message = error instanceof Error ? error.message : String(error);
    const panel = root.querySelector<HTMLElement>('.aop-detail');
    if (panel) {
        panel.textContent = `Não foi possível carregar os dados do mapa: ${message}`;
    }
}

document.querySelectorAll<HTMLElement>('.aop-map').forEach((root) => {
    initMap(root).catch((error: unknown) => {
        reportFailure(root, error);
    });
});
