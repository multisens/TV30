export enum EventType {
  attribution = "attribution",
  preparation = "preparation",
  presentation = "presentation",
  selection = "selection",
  view = "view",
}

export enum Action {
  start = "start",
  stop = "stop",
  abort = "abort",
  pause = "pause",
  resume = "resume",
  set = "set",
}

export enum Transition {
  starts = "starts",
  stops = "stops",
  aborts = "aborts",
  pauses = "pauses",
  resumes = "resumes",
}

export type NodeMetadata = {
  nodeId: string;
  nodeSrc?: string;
  appId: string;
  type: string;
  properties?: { name: string; value: string }[];
};

export type ActionMetadata = {
  nodeId: string;
  label?: string;
  appId: string;
  eventType: EventType;
  action: Action;
  value?: string;
  delay?: number;
};

export type TransitionMetadata = {
  nodeId: string;
  label?: string;
  appId: string;
  eventType: EventType;
  transition: Transition;
  value?: string;
  user?: string;
};

export type CapabilitiesMetadata = {
  type?: EffectType;
  capabilities: (
    | { name: "state"; value: State }
    | { name: "locator"; value: Locator }
    | { name: "preparationTime"; value: PreparationTime }
  )[];
};

export type ControlMetadata = {
  effectType: EffectType;
  action: Action;
  properties?: { name: string; value: any }[];
};

export type EffectType =
  | "LightType"
  | "TemperatureType"
  | "WindType"
  | "ScentType"
  | "VibrationType"
  | "SprayingType"
  | "FogType";
export type State = "preparing" | "prepared" | "playing" | "stopped" | "idle";
export type Locator = string;
export type PreparationTime = number;

export type DeviceCapabilities = {
  effectType: EffectType;
  state: State;
  locator?: Locator;
  preparationTime?: PreparationTime;
};
