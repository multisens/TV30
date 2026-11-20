// Lifecycle machine (components/lifecycle-machine.astro): the rules of the
// application lifecycle manager of aop-cc for one BALD entry (ABNT NBR 25608,
// 10.1.3). An AUTOSTART or STORED_AUTOSTART is launched when the entry
// becomes that code; a STORED_AUTOSTART waits for the cache to have it
// complete; DESTROY, KILL, STORED_REMOVE and leaving the BALD end it; an end
// asked by the viewer holds while the code stays the same.

import { requiredElement } from './required-element';

interface State {
    code: string;
    running: boolean;
    pending: boolean;
    cacheComplete: boolean;
}

const DIAGRAM = 'lifecycle machine';
const AUTOSTART = 'AUTOSTART';
const STORED_AUTOSTART = 'STORED_AUTOSTART';
const STORED_REMOVE = 'STORED_REMOVE';
const OUT_OF_BALD = '';
const LAUNCHED_CODES = [AUTOSTART, STORED_AUTOSTART];
const ENDING_CODES = ['DESTROY', 'KILL', STORED_REMOVE, OUT_OF_BALD];
const PRESENT_CODES = ['PRESENT', 'STORED_PRESENT'];
const INITIAL_STATE: State = { code: OUT_OF_BALD, running: false, pending: false, cacheComplete: false };
const SHOWING_BOOTSTRAP = 'Bootstrap Application, em modo de informação';
const SHOWING_APPLICATION = 'A aplicação da emissora, na origem ctx-<h>';
const SHOWING_WAITING = 'Bootstrap Application; o lançamento espera o cache';

function initMachine(root: HTMLElement): void {
    const codeButtons = Array.from(root.querySelectorAll<HTMLButtonElement>('[data-code]'));
    const cacheInput = requiredElement<HTMLInputElement>(root, '[data-input="cache"]', DIAGRAM);
    const backButton = requiredElement<HTMLButtonElement>(root, '[data-action="back"]', DIAGRAM);
    const resetButton = requiredElement<HTMLButtonElement>(root, '[data-action="reset"]', DIAGRAM);
    const screen = requiredElement<HTMLElement>(root, '[data-screen]', DIAGRAM);
    const showing = requiredElement<HTMLElement>(root, '[data-showing]', DIAGRAM);
    const present = requiredElement<HTMLElement>(root, '[data-present]', DIAGRAM);
    const log = requiredElement<HTMLElement>(root, '[data-log]', DIAGRAM);

    let state: State = { ...INITIAL_STATE };

    function note(text: string): void {
        const item = document.createElement('li');
        item.textContent = text;
        log.append(item);
    }

    function start(): void {
        state.running = true;
        state.pending = false;
        note('started: a aplicação vai para a camada de gráficos e a origem, para origins:associated');
    }

    function end(reason: string): void {
        state.running = false;
        note(`ended (${reason}): a Bootstrap Application volta`);
    }

    function replace(): void {
        note('ended: a aplicação no ar sai antes de a nova entrar');
        start();
    }

    function launchPending(): void {
        if (!state.pending) {
            return;
        }
        if (state.code === STORED_AUTOSTART && !state.cacheComplete) {
            note('lançamento pendente: o cache ainda não tem a aplicação completa');
            return;
        }
        if (state.running) {
            replace();
            return;
        }
        start();
    }

    function changeCode(code: string): void {
        const previous = state.code;
        if (code === previous) {
            return;
        }
        state.code = code;
        if (state.running && ENDING_CODES.includes(code)) {
            end(code === OUT_OF_BALD ? 'saiu da BALD' : code);
        }
        if (code === STORED_REMOVE && state.cacheComplete) {
            state.cacheComplete = false;
            note('os arquivos do contexto saem do cache');
        }
        state.pending = LAUNCHED_CODES.includes(code);
        if (state.pending) {
            note(`${code} recebido: lançamento pendente`);
        }
        launchPending();
    }

    function render(): void {
        codeButtons.forEach((button) => {
            button.setAttribute('aria-pressed', String(button.dataset.code === state.code));
        });
        cacheInput.checked = state.cacheComplete;
        backButton.disabled = !state.running;
        let text = SHOWING_BOOTSTRAP;
        if (state.running) {
            text = SHOWING_APPLICATION;
        } else if (state.pending) {
            text = SHOWING_WAITING;
        }
        showing.textContent = text;
        screen.dataset.screen = state.running ? 'application' : 'bootstrap';
        present.hidden = !PRESENT_CODES.includes(state.code);
    }

    codeButtons.forEach((button) => {
        button.addEventListener('click', () => {
            changeCode(button.dataset.code ?? OUT_OF_BALD);
            render();
        });
    });
    cacheInput.addEventListener('change', () => {
        state.cacheComplete = cacheInput.checked;
        note(state.cacheComplete ? 'o cache completou a aplicação' : 'o cache perdeu a aplicação');
        launchPending();
        render();
    });
    backButton.addEventListener('click', () => {
        end('pedido do espectador; não volta enquanto o controlCode for o mesmo');
        render();
    });
    resetButton.addEventListener('click', () => {
        state = { ...INITIAL_STATE };
        log.replaceChildren();
        render();
    });
    render();
}


document.querySelectorAll<HTMLElement>('[data-lifecycle-machine]').forEach((root) => {
    initMachine(root);
});
