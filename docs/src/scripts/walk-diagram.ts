// Walk-through of the diagrams with steps: the play button selects each step
// in order; a click on a step stops the walk.
import { showBlock } from './detail-diagram';

const STEP_INTERVAL_MS = 2600;
const STOP_LABEL = 'Parar';

function initWalk(root: HTMLElement): void {
    const playButton = root.querySelector<HTMLButtonElement>('.dg-play');
    const steps = Array.from(root.querySelectorAll<HTMLElement>('[data-step]'));
    if (!playButton || steps.length === 0) {
        throw new Error('walk diagram: play button or steps missing');
    }
    const button = playButton;
    const playLabelValue = button.dataset.playLabel;
    if (!playLabelValue) {
        throw new Error('walk diagram: play button without data-play-label');
    }
    const playLabel = playLabelValue;

    let timer: number | undefined;
    let index = 0;

    function stop(): void {
        window.clearInterval(timer);
        timer = undefined;
        button.textContent = playLabel;
        button.setAttribute('aria-pressed', 'false');
    }

    function advance(): void {
        index = index + 1;
        if (index >= steps.length) {
            stop();
            return;
        }
        showBlock(root, steps[index]);
    }

    function start(): void {
        index = 0;
        showBlock(root, steps[index]);
        timer = window.setInterval(advance, STEP_INTERVAL_MS);
        button.textContent = STOP_LABEL;
        button.setAttribute('aria-pressed', 'true');
    }

    button.addEventListener('click', () => {
        if (timer === undefined) {
            start();
        } else {
            stop();
        }
    });

    steps.forEach((step) => {
        step.addEventListener('click', () => {
            if (timer !== undefined) {
                stop();
            }
        });
    });
}

document.querySelectorAll<HTMLElement>('[data-walk-diagram]').forEach((root) => {
    initWalk(root);
});
