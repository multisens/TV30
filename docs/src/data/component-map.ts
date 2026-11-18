// Types of the component maps (components/component-map.astro). Coordinates
// are in the units of the SVG viewBox.

export type Channel = 'http' | 'mqtt' | 'state' | 'websocket' | 'discovery';

export type BlockKind = 'node' | 'bus' | 'group' | 'new';

export type Tone = 'platform' | 'webservices' | 'screen' | 'app' | 'mqtt' | 'state' | 'discovery' | 'infra';

export interface Zone {
    id: string;
    title: string;
    subtitle?: string;
    x: number;
    y: number;
    width: number;
    height: number;
}

export interface Block {
    id: string;
    kind: BlockKind;
    parent?: string;
    tone?: Tone;
    title: string;
    titleX?: number;
    subtitle?: string;
    x: number;
    y: number;
    width: number;
    height: number;
    outline?: string;
    detailTitle: string;
    detail: string;
}

export interface Link {
    id: string;
    channel: Channel;
    ends: [string, string];
    path: string;
    planned?: boolean;
    label?: { text: string; x: number; y: number };
    detailTitle: string;
    detail: string;
}

export interface RowLabel {
    text: string;
    x?: number;
    y: number;
}

export interface ComponentMap {
    width: number;
    height: number;
    zones: Zone[];
    rowLabels: RowLabel[];
    blocks: Block[];
    links: Link[];
}

export const CHANNEL_LABELS: Record<Channel, string> = {
    http: 'HTTP',
    mqtt: 'mensageria (MQTT)',
    state: 'armazenamento (Redis)',
    websocket: 'WebSocket',
    discovery: 'descoberta (SSDP)',
};
