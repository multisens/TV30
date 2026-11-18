// Types of the name trees (components/name-tree.astro): a list of names,
// split by a separator into branches, each name a leaf with its facts.

export interface Fact {
    label: string;
    // HTML.
    value: string;
}

export interface TreeEntry {
    name: string;
    badges: string[];
    facts: Fact[];
    // HTML.
    detail: string;
}

export interface NameTree {
    separator: string;
    entries: TreeEntry[];
}

export interface TreeNode {
    label: string;
    entry?: TreeEntry;
    children: TreeNode[];
}

// Builds the tree of the names, joining into one node each branch without an
// entry of its own and with a single child.
export function buildTree(tree: NameTree): TreeNode[] {
    const root: TreeNode = { label: '', children: [] };
    tree.entries.forEach((entry) => {
        insertEntry(root, entry, tree.separator);
    });
    return root.children.map((node) => compress(node, tree.separator));
}

function insertEntry(root: TreeNode, entry: TreeEntry, separator: string): void {
    let node = root;
    entry.name.split(separator).forEach((segment) => {
        let child = node.children.find((item) => item.label === segment);
        if (!child) {
            child = { label: segment, children: [] };
            node.children.push(child);
        }
        node = child;
    });
    if (node.entry) {
        throw new Error(`name tree: repeated name ${entry.name}`);
    }
    node.entry = entry;
}

function compress(node: TreeNode, separator: string): TreeNode {
    let current = node;
    while (!current.entry && current.children.length === 1) {
        const child = current.children[0];
        current = {
            label: `${current.label}${separator}${child.label}`,
            entry: child.entry,
            children: child.children,
        };
    }
    return {
        label: current.label,
        entry: current.entry,
        children: current.children.map((child) => compress(child, separator)),
    };
}
