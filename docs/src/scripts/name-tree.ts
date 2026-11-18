// Interaction of the name trees: a click on a leaf shows its facts in the
// detail panel (detail-diagram.ts); two buttons open or close every branch.
import './detail-diagram';

function initTree(root: HTMLElement): void {
    const branches = Array.from(root.querySelectorAll<HTMLDetailsElement>('details.nt-branch'));
    root.querySelectorAll<HTMLButtonElement>('[data-tree-action]').forEach((button) => {
        button.addEventListener('click', () => {
            const open = button.dataset.treeAction === 'open';
            branches.forEach((branch) => {
                branch.open = open;
            });
        });
    });
}

document.querySelectorAll<HTMLElement>('[data-name-tree]').forEach((root) => {
    initTree(root);
});
