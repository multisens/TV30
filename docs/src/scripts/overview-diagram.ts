// Interaction of the overview diagram: a click on a block shows its
// description in the detail panel.

function initDiagram(root: HTMLElement): void {
    root.addEventListener('click', (event) => {
        if (!(event.target instanceof Element)) {
            return;
        }
        const node = event.target.closest<HTMLElement>('[data-node]');
        if (!node || !root.contains(node)) {
            return;
        }
        const id = node.dataset.node;
        if (!id) {
            throw new Error('overview diagram: block without data-node');
        }
        selectNode(root, node);
        showDetail(root, id);
    });
}

function selectNode(root: HTMLElement, node: HTMLElement): void {
    root.querySelectorAll('.is-selected').forEach((item) => {
        item.classList.remove('is-selected');
    });
    node.classList.add('is-selected');
}

function showDetail(root: HTMLElement, id: string): void {
    const details = root.querySelectorAll<HTMLElement>('[data-detail]');
    const target = root.querySelector<HTMLElement>(`[data-detail="${id}"]`);
    if (!target) {
        throw new Error(`overview diagram: no detail for ${id}`);
    }
    details.forEach((detail) => {
        detail.hidden = detail !== target;
    });
}

document.querySelectorAll<HTMLElement>('.ov-diagram').forEach((root) => {
    initDiagram(root);
});
