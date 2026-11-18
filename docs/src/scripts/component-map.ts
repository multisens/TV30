// Interaction of the component map: the channel buttons show one channel at
// a time and clear the highlight; a click on a block or a link shows all
// channels again and highlights its links and the blocks at their ends (for a
// group, those of the blocks inside it); Enter and Space act as a click.
import { showBlock } from './detail-diagram';

const LINKED_CLASS = 'is-linked';
const FOCUS_CLASS = 'has-focus';
const ALL_CHANNELS = 'all';
const IN_CHANNEL_CLASS = 'in-channel';

function initMap(root: HTMLElement): void {
    const filters = Array.from(root.querySelectorAll<HTMLButtonElement>('[data-filter]'));
    const items = Array.from(root.querySelectorAll<SVGGElement>('svg [data-node]'));

    filters.forEach((filter) => {
        filter.addEventListener('click', () => {
            selectChannel(root, filters, filter);
        });
    });

    items.forEach((item) => {
        item.addEventListener('click', () => {
            selectItem(root, filters, item);
        });
        item.addEventListener('keydown', (event) => {
            if (event.key !== 'Enter' && event.key !== ' ') {
                return;
            }
            event.preventDefault();
            showBlock(root, item);
            selectItem(root, filters, item);
        });
    });
}

function selectChannel(root: HTMLElement, filters: HTMLButtonElement[], chosen: HTMLButtonElement): void {
    clearHighlight(root);
    showChannel(root, filters, chosen);
}

function selectItem(root: HTMLElement, filters: HTMLButtonElement[], item: SVGGElement): void {
    const all = filters.find((filter) => filter.dataset.filter === ALL_CHANNELS);
    if (!all) {
        throw new Error('component map: no filter for all channels');
    }
    showChannel(root, filters, all);
    highlight(root, item);
}

function showChannel(root: HTMLElement, filters: HTMLButtonElement[], chosen: HTMLButtonElement): void {
    const channel = chosen.dataset.filter;
    if (!channel) {
        throw new Error('component map: filter without data-filter');
    }
    root.dataset.channel = channel;
    filters.forEach((filter) => {
        filter.setAttribute('aria-pressed', String(filter === chosen));
    });
    root.querySelectorAll<SVGGElement>('svg [data-channel]').forEach((link) => {
        link.classList.toggle(IN_CHANNEL_CLASS, link.dataset.channel === channel);
    });
}

function highlight(root: HTMLElement, item: SVGGElement): void {
    const id = nodeIdOf(item);
    const children = Array.from(root.querySelectorAll<SVGGElement>(`svg [data-parent="${id}"]`));
    const sources = [id, ...children.map(nodeIdOf)];
    const linked = new Set<string>(sources);
    const links = Array.from(root.querySelectorAll<SVGGElement>('svg [data-ends]'));
    links.forEach((link) => {
        const ends = endsOf(link);
        const touches = link === item || ends.some((end) => sources.includes(end));
        if (touches) {
            linked.add(nodeIdOf(link));
            ends.forEach((end) => linked.add(end));
        }
    });
    root.querySelectorAll<SVGGElement>('svg [data-node]').forEach((element) => {
        const isLinked = linked.has(nodeIdOf(element));
        element.classList.toggle(LINKED_CLASS, isLinked);
    });
    root.classList.add(FOCUS_CLASS);
}

function clearHighlight(root: HTMLElement): void {
    root.classList.remove(FOCUS_CLASS);
    root.querySelectorAll(`.${LINKED_CLASS}`).forEach((element) => {
        element.classList.remove(LINKED_CLASS);
    });
}

function nodeIdOf(element: SVGGElement): string {
    const id = element.dataset.node;
    if (!id) {
        throw new Error('component map: item without data-node');
    }
    return id;
}

function endsOf(link: SVGGElement): string[] {
    const ends = link.dataset.ends;
    if (!ends) {
        throw new Error('component map: link without data-ends');
    }
    return ends.split(' ');
}

document.querySelectorAll<HTMLElement>('[data-component-map]').forEach((root) => {
    initMap(root);
});
