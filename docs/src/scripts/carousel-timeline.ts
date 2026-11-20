// Carousel timeline (components/carousel-timeline.astro): draws the passes and
// the availability of each object for the instant of tuning, and tells what
// the object proxy answers at the instant now. The rule is that of aop-cc: an
// object is available after its last complete pass begun at or after the
// tuning, until maxExpiresDelta from the start of that pass (ATSC A/331,
// A.3.3.2.3).

import { requiredElement } from './required-element';

interface CarouselObject {
    name: string;
    tsi: number;
    cyclePeriod: number;
    order: number;
    count: number;
    maxExpiresDelta: number | null;
}

interface Span {
    from: number;
    to: number;
}

interface Availability {
    span: Span;
    expires: boolean;
}

interface TimelineEvent {
    at: number;
    name: string;
    kind: 'available' | 'expired';
}

const DIAGRAM = 'carousel timeline';
const SVG_NAMESPACE = 'http://www.w3.org/2000/svg';
const PASS_Y = 0.08;
const PASS_HEIGHT = 0.4;
const AVAILABLE_Y = 0.58;
const AVAILABLE_HEIGHT = 0.34;
const MARKER_WIDTH = 0.25;
const PLAY_STEP_SECONDS = 0.5;
const PLAY_INTERVAL_MS = 250;
const STOP_LABEL = 'Parar';
const NUMBER_FORMAT = new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 1 });

function initTimeline(root: HTMLElement): void {
    const objects = JSON.parse(requiredData(root, 'objects')) as CarouselObject[];
    const windowSeconds = Number(requiredData(root, 'window'));
    const tunedInput = requiredElement<HTMLInputElement>(root, '[data-input="tuned"]', DIAGRAM);
    const nowInput = requiredElement<HTMLInputElement>(root, '[data-input="now"]', DIAGRAM);
    const tunedOutput = requiredElement<HTMLOutputElement>(root, '[data-output="tuned"]', DIAGRAM);
    const nowOutput = requiredElement<HTMLOutputElement>(root, '[data-output="now"]', DIAGRAM);
    const playButton = requiredElement<HTMLButtonElement>(root, '.dg-play', DIAGRAM);
    const statusBody = requiredElement<HTMLElement>(root, '[data-status]', DIAGRAM);
    const eventList = requiredElement<HTMLElement>(root, '[data-events]', DIAGRAM);
    const tracks = Array.from(root.querySelectorAll<SVGSVGElement>('[data-track]'));
    if (tracks.length !== objects.length) {
        throw new Error('carousel timeline: one track per object expected');
    }
    const playLabel = playButton.dataset.playLabel ?? '';

    let timer: number | undefined;

    function render(): void {
        const tuned = Number(tunedInput.value);
        const now = Number(nowInput.value);
        tunedOutput.textContent = seconds(tuned);
        nowOutput.textContent = seconds(now);
        const events: TimelineEvent[] = [];
        statusBody.replaceChildren();
        objects.forEach((object, index) => {
            const availabilities = availabilitiesOf(object, tuned, windowSeconds);
            drawTrack(tracks[index], object, availabilities, tuned, now, windowSeconds);
            statusBody.append(statusRow(object, availabilities, tuned, now));
            events.push(...eventsOf(object, availabilities, now));
        });
        events.sort((first, second) => first.at - second.at);
        eventList.replaceChildren(...events.map(eventItem));
    }

    function stop(): void {
        window.clearInterval(timer);
        timer = undefined;
        playButton.textContent = playLabel;
        playButton.setAttribute('aria-pressed', 'false');
    }

    function tick(): void {
        const next = Number(nowInput.value) + PLAY_STEP_SECONDS;
        if (next > windowSeconds) {
            stop();
            return;
        }
        nowInput.value = String(next);
        render();
    }

    function start(): void {
        if (Number(nowInput.value) >= windowSeconds) {
            nowInput.value = tunedInput.value;
        }
        timer = window.setInterval(tick, PLAY_INTERVAL_MS);
        playButton.textContent = STOP_LABEL;
        playButton.setAttribute('aria-pressed', 'true');
    }

    tunedInput.addEventListener('input', render);
    nowInput.addEventListener('input', () => {
        stop();
        render();
    });
    playButton.addEventListener('click', () => {
        if (timer === undefined) {
            start();
        } else {
            stop();
        }
    });
    render();
}

// The spans in which the object is available, one per pass begun at or after
// the tuning, joined when one pass renews the availability of the previous.
function availabilitiesOf(object: CarouselObject, tuned: number, windowSeconds: number): Availability[] {
    const slice = object.cyclePeriod / object.count;
    const availabilities: Availability[] = [];
    for (let lap = 0; lap * object.cyclePeriod < windowSeconds; lap = lap + 1) {
        const passStart = lap * object.cyclePeriod + object.order * slice;
        if (passStart < tuned) {
            continue;
        }
        const nextPassEnd = passStart + object.cyclePeriod + slice;
        let to = nextPassEnd;
        let expires = false;
        if (object.maxExpiresDelta !== null && passStart + object.maxExpiresDelta < nextPassEnd) {
            to = passStart + object.maxExpiresDelta;
            expires = true;
        }
        const span = { from: passStart + slice, to: to };
        const last = availabilities[availabilities.length - 1];
        if (last && !last.expires && last.span.to >= span.from) {
            last.span.to = span.to;
            last.expires = expires;
        } else {
            availabilities.push({ span: span, expires: expires });
        }
    }
    return availabilities;
}

function drawTrack(
    track: SVGSVGElement,
    object: CarouselObject,
    availabilities: Availability[],
    tuned: number,
    now: number,
    windowSeconds: number,
): void {
    const slice = object.cyclePeriod / object.count;
    track.replaceChildren();
    for (let lap = 0; lap * object.cyclePeriod < windowSeconds; lap = lap + 1) {
        const passStart = lap * object.cyclePeriod + object.order * slice;
        const passClass = passStart < tuned ? 'ct-pass ct-pass-ignored' : 'ct-pass';
        track.append(rect(passStart, PASS_Y, slice, PASS_HEIGHT, passClass));
    }
    availabilities.forEach((availability) => {
        const width = Math.min(availability.span.to, windowSeconds) - availability.span.from;
        if (width > 0) {
            track.append(rect(availability.span.from, AVAILABLE_Y, width, AVAILABLE_HEIGHT, 'ct-available'));
        }
    });
    track.append(rect(tuned, 0, MARKER_WIDTH, 1, 'ct-marker-tuned'));
    track.append(rect(now, 0, MARKER_WIDTH, 1, 'ct-marker-now'));
}

function statusRow(object: CarouselObject, availabilities: Availability[], tuned: number, now: number): HTMLElement {
    const row = document.createElement('tr');
    const current = availabilities.find((item) => item.span.from <= now && now < item.span.to);
    let answer = '404';
    let reason = '';
    if (now < tuned) {
        reason = 'o serviço ainda não foi sintonizado';
    } else if (current) {
        const passStart = lastCompletePassStart(object, now);
        const slice = object.cyclePeriod / object.count;
        answer = '200';
        reason = `passou inteiro de ${seconds(passStart)} a ${seconds(passStart + slice)}`;
        if (object.maxExpiresDelta !== null) {
            reason = `${reason}; vence em ${seconds(passStart + object.maxExpiresDelta)}`;
        }
    } else {
        const next = availabilities.find((item) => item.span.from > now);
        const expired = availabilities.filter((item) => item.span.to <= now).pop();
        const after = next ? `volta em ${seconds(next.span.from)}, no fim da próxima passagem` : 'não volta nesta janela';
        if (expired) {
            reason = `venceu em ${seconds(expired.span.to)}; ${after}`;
        } else {
            reason = `espera a primeira passagem completa depois da sintonia; ${after}`;
        }
    }
    row.append(cell(object.name), cell(answer), cell(reason));
    return row;
}

// Start of the last pass of the object complete at the instant now.
function lastCompletePassStart(object: CarouselObject, now: number): number {
    const slice = object.cyclePeriod / object.count;
    const sinceFirstEnd = now - (object.order + 1) * slice;
    const lap = Math.floor(sinceFirstEnd / object.cyclePeriod);
    return lap * object.cyclePeriod + object.order * slice;
}

function eventsOf(object: CarouselObject, availabilities: Availability[], now: number): TimelineEvent[] {
    const events: TimelineEvent[] = [];
    availabilities.forEach((availability) => {
        if (availability.span.from <= now) {
            events.push({ at: availability.span.from, name: object.name, kind: 'available' });
        }
        if (availability.expires && availability.span.to <= now) {
            events.push({ at: availability.span.to, name: object.name, kind: 'expired' });
        }
    });
    return events;
}

function eventItem(event: TimelineEvent): HTMLElement {
    const item = document.createElement('li');
    const topic = document.createElement('code');
    topic.textContent = `tlm/object/1002/${event.kind}`;
    item.append(`${seconds(event.at)} `, topic, ` ${event.name}`);
    return item;
}

function rect(x: number, y: number, width: number, height: number, className: string): SVGRectElement {
    const element = document.createElementNS(SVG_NAMESPACE, 'rect');
    element.setAttribute('x', String(x));
    element.setAttribute('y', String(y));
    element.setAttribute('width', String(width));
    element.setAttribute('height', String(height));
    element.setAttribute('class', className);
    return element;
}

function cell(text: string): HTMLElement {
    const element = document.createElement('td');
    element.textContent = text;
    return element;
}

function seconds(value: number): string {
    return `${NUMBER_FORMAT.format(value)} s`;
}

function requiredData(root: HTMLElement, name: string): string {
    const value = root.dataset[name];
    if (value === undefined) {
        throw new Error(`carousel timeline: data-${name} missing`);
    }
    return value;
}


document.querySelectorAll<HTMLElement>('[data-carousel-timeline]').forEach((root) => {
    initTimeline(root);
});
