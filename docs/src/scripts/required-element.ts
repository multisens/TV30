// The element of a diagram under a selector; a missing one is an error of the
// page, named after the diagram.
export function requiredElement<T extends Element>(root: HTMLElement, selector: string, diagram: string): T {
    const element = root.querySelector<T>(selector);
    if (!element) {
        throw new Error(`${diagram}: ${selector} missing`);
    }
    return element;
}
