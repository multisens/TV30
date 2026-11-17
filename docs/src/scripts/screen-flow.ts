// Walk-through of the screen flow diagram: the play button selects each
// screen in order; a click on a screen stops the walk.
import { showBlock } from './detail-diagram';

const STEP_INTERVAL_MS = 2600;
const PLAY_LABEL = 'Percorrer o fluxo';
const STOP_LABEL = 'Parar';

function initFlow(root: HTMLElement): void {
    const playButton = root.querySelector<HTMLButtonElement>('.sf-play');
    const steps = Array.from(root.querySelectorAll<HTMLElement>('[data-step]'));
    if (!playButton || steps.length === 0) {
        throw new Error('screen flow: play button or steps missing');
    }
    const button = playButton;

    let timer: number | undefined;
    let index = 0;

    function stop(): void {
        window.clearInterval(timer);
        timer = undefined;
        button.textContent = PLAY_LABEL;
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

document.querySelectorAll<HTMLElement>('[data-screen-flow]').forEach((root) => {
    initFlow(root);
});
