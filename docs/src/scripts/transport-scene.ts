// Scene "Do sinal à tela" (components/transport-scene.astro): each step lights
// the blocks of its messages, runs a packet from block to block, one message
// after the other, and leaves the TV screen as the viewer sees it.
import type { SceneHop, SceneStep } from '../data/transport-scene';
import { requiredElement } from './required-element';

const DIAGRAM = 'transport scene';
const HOP_MS = 900;
const STEP_PAUSE_MS = 2200;
const DOT_RADIUS_PX = 6;
const STOP_LABEL = 'Parar';
const ACTIVE_CLASS = 'is-active';
const ABORT_ERROR = 'AbortError';
const REDUCED_MOTION = window.matchMedia('(prefers-reduced-motion: reduce)');

function initScene(root: HTMLElement): void {
    const stepsData = root.dataset.steps;
    if (stepsData === undefined) {
        throw new Error(`${DIAGRAM}: data-steps missing`);
    }
    const steps = JSON.parse(stepsData) as SceneStep[];
    const stage = requiredElement<HTMLElement>(root, '[data-stage]', DIAGRAM);
    const packet = requiredElement<HTMLElement>(root, '[data-packet]', DIAGRAM);
    const packetLabel = requiredElement<HTMLElement>(root, '[data-packet-label]', DIAGRAM);
    const screen = requiredElement<HTMLElement>(root, '[data-screen]', DIAGRAM);
    const counter = requiredElement<HTMLElement>(root, '[data-counter]', DIAGRAM);
    const previousButton = requiredElement<HTMLButtonElement>(root, '[data-action="previous"]', DIAGRAM);
    const nextButton = requiredElement<HTMLButtonElement>(root, '[data-action="next"]', DIAGRAM);
    const playButton = requiredElement<HTMLButtonElement>(root, '[data-action="play"]', DIAGRAM);
    const playLabel = playButton.dataset.playLabel ?? '';
    const details = Array.from(root.querySelectorAll<HTMLElement>('[data-detail]'));
    const nodes = Array.from(root.querySelectorAll<HTMLElement>('[data-node]'));

    let current = -1;
    let run = 0;
    let playing = false;
    let playRun = 0;

    function nodeOf(id: string): HTMLElement {
        const node = nodes.find((item) => item.dataset.node === id);
        if (!node) {
            throw new Error(`${DIAGRAM}: no block ${id}`);
        }
        return node;
    }

    // The center of a block, relative to the stage.
    function centerOf(id: string): { x: number; y: number } {
        const stageBox = stage.getBoundingClientRect();
        const box = nodeOf(id).getBoundingClientRect();
        return {
            x: box.left - stageBox.left + box.width / 2,
            y: box.top - stageBox.top + box.height / 2,
        };
    }

    // Runs the packet of one message; false when the step was left meanwhile.
    async function runHop(hop: SceneHop, stepRun: number): Promise<boolean> {
        const from = centerOf(hop.from);
        const to = centerOf(hop.to);
        packet.className = `ts-packet ts-${hop.channel}`;
        packetLabel.textContent = hop.label;
        packet.hidden = false;
        const animation = packet.animate([
            { transform: `translate(${from.x - DOT_RADIUS_PX}px, ${from.y - DOT_RADIUS_PX}px)` },
            { transform: `translate(${to.x - DOT_RADIUS_PX}px, ${to.y - DOT_RADIUS_PX}px)` },
        ], { duration: HOP_MS, easing: 'ease-in-out', fill: 'forwards' });
        try {
            await animation.finished;
        } catch (error) {
            if (error instanceof DOMException && error.name === ABORT_ERROR) {
                return false;
            }
            throw error;
        }
        return stepRun === run;
    }

    function stopPacket(): void {
        packet.getAnimations().forEach((animation) => {
            animation.cancel();
        });
        packet.hidden = true;
    }

    function showScreen(step: SceneStep): void {
        screen.dataset.view = step.screen.view;
        screen.dataset.selected = String(step.screen.selected);
        screen.dataset.carousel = step.screen.carousel;
        screen.dataset.key = String(step.screen.key);
    }

    function showDetail(step: SceneStep, index: number): void {
        details.forEach((detail) => {
            detail.hidden = detail.dataset.detail !== step.id;
        });
        counter.textContent = `${index + 1} / ${steps.length}`;
        const active = new Set<string>();
        step.hops.forEach((hop) => {
            active.add(hop.from);
            active.add(hop.to);
        });
        nodes.forEach((node) => {
            node.classList.toggle(ACTIVE_CLASS, active.has(node.dataset.node ?? ''));
        });
        previousButton.disabled = index === 0;
        nextButton.disabled = index === steps.length - 1;
    }

    // Shows a step and runs its messages; false when it was left meanwhile.
    async function showStep(index: number): Promise<boolean> {
        run = run + 1;
        const stepRun = run;
        current = index;
        const step = steps[index];
        stopPacket();
        showDetail(step, index);
        if (!REDUCED_MOTION.matches) {
            for (const hop of step.hops) {
                const finished = await runHop(hop, stepRun);
                if (!finished) {
                    return false;
                }
            }
        }
        stopPacket();
        showScreen(step);
        return stepRun === run;
    }

    function stopPlay(): void {
        playing = false;
        playRun = playRun + 1;
        playButton.textContent = playLabel;
        playButton.setAttribute('aria-pressed', 'false');
    }

    async function play(): Promise<void> {
        playing = true;
        playRun = playRun + 1;
        const thisPlay = playRun;
        playButton.textContent = STOP_LABEL;
        playButton.setAttribute('aria-pressed', 'true');
        let index = current + 1;
        if (index >= steps.length) {
            index = 0;
        }
        while (index < steps.length) {
            const finished = await showStep(index);
            if (!finished || thisPlay !== playRun) {
                return;
            }
            await new Promise((resolve) => {
                window.setTimeout(resolve, STEP_PAUSE_MS);
            });
            if (thisPlay !== playRun) {
                return;
            }
            index = index + 1;
        }
        stopPlay();
    }

    function goTo(index: number): void {
        stopPlay();
        showStep(index).catch(reportError);
    }

    previousButton.addEventListener('click', () => {
        goTo(Math.max(current - 1, 0));
    });
    nextButton.addEventListener('click', () => {
        goTo(Math.min(current + 1, steps.length - 1));
    });
    playButton.addEventListener('click', () => {
        if (playing) {
            stopPlay();
            return;
        }
        play().catch(reportError);
    });
    previousButton.disabled = true;
    counter.textContent = `0 / ${steps.length}`;
}

document.querySelectorAll<HTMLElement>('[data-transport-scene]').forEach((root) => {
    initScene(root);
});
