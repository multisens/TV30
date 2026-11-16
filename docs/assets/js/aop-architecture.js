// Interaction of the TV 3.0 AoP units diagram: detail panel on click and
// legend filter by status.

const STATUS_LABELS = {
    implemented: 'Implementado',
    partial: 'Parcial',
    absent: 'No escopo, não implementado',
    out: 'Fora do escopo',
};

async function initDiagram(root) {
    const response = await fetch(root.dataset.unitsUrl);
    if (!response.ok) {
        throw new Error(`units data: HTTP ${response.status}`);
    }
    const data = await response.json();
    const unitsById = new Map(data.units.map((unit) => [unit.id, unit]));
    const groupsByKey = new Map(data.groups.map((group) => [group.key, group]));
    const panel = root.querySelector('.aop-detail');

    root.addEventListener('click', (event) => {
        const target = event.target.closest('[data-unit], [data-group], [data-filter]');
        if (!target || !root.contains(target)) {
            return;
        }
        if (target.dataset.filter) {
            toggleFilter(root, target);
            return;
        }
        selectElement(root, target);
        if (target.dataset.unit) {
            showUnit(panel, unitsById.get(target.dataset.unit));
        } else {
            const group = groupsByKey.get(target.dataset.group);
            const members = data.units.filter((unit) => unit.group === group.key);
            showGroup(panel, group, members);
        }
    });

    panel.addEventListener('click', (event) => {
        const target = event.target.closest('[data-member]');
        if (!target) {
            return;
        }
        showUnit(panel, unitsById.get(target.dataset.member));
    });
}

function toggleFilter(root, button) {
    const status = button.dataset.filter;
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

function selectElement(root, element) {
    root.querySelectorAll('.is-selected').forEach((item) => {
        item.classList.remove('is-selected');
    });
    element.classList.add('is-selected');
}

function showUnit(panel, unit) {
    const fields = [
        ['Estado', statusBadge(unit.status)],
        ['Natureza', text(unit.nature)],
        ['Seções da norma', text(unit.sections)],
    ];
    if (unit.parent) {
        fields.push(['Parte de', code(unit.parent)]);
    }
    if (unit.group) {
        fields.push(['Grupo', text(unit.group)]);
    }
    if (unit.note) {
        fields.push(['Nota', text(unit.note)]);
    }
    panel.replaceChildren(heading(unit.id), fieldList(fields));
}

function showGroup(panel, group, members) {
    const counts = Object.keys(STATUS_LABELS)
        .map((status) => {
            const count = members.filter((unit) => unit.status === status).length;
            return `${STATUS_LABELS[status]}: ${count}`;
        })
        .join(' · ');
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

function heading(value) {
    const element = document.createElement('p');
    element.className = 'aop-detail-id';
    element.textContent = value;
    return element;
}

function fieldList(fields) {
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

function statusBadge(status) {
    const element = document.createElement('span');
    element.className = `aop-detail-status status-${status}`;
    element.textContent = STATUS_LABELS[status];
    return element;
}

function code(value) {
    const element = document.createElement('code');
    element.textContent = value;
    return element;
}

function text(value) {
    return document.createTextNode(value);
}

function reportFailure(root, error) {
    const panel = root.querySelector('.aop-detail');
    panel.textContent = `Não foi possível carregar os dados do diagrama: ${error.message}`;
}

document.querySelectorAll('.aop-arch').forEach((root) => {
    initDiagram(root).catch((error) => {
        reportFailure(root, error);
    });
});
