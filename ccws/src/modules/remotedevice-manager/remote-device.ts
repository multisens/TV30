import core from "../../core";
import mqttClient, { TOPICS } from "../../mqtt-client";
import { ReqBody } from "../remotedevice-api/service";
import {
  Action,
  CapabilitiesMetadata,
  ControlMetadata,
  DeviceCapabilities,
  EffectType,
  EventType,
  type ActionMetadata,
  type NodeMetadata,
  type TransitionMetadata,
} from "./types";
import { WebSocket, WebSocketServer } from "ws";
import { removeRemoteDevice } from "./manager";

enum InterfaceType {
  area = "area",
  property = "property",
  port = "port",
}

enum NodeType {
  media = "media",
  context = "context",
  switch = "switch",
}

type PropertiesType = { name: string; value: string }[];

export type AppNode = {
  id: string;
  type: NodeType;
  mimeType: string;
  device: string;
};

export type NodeInterface = {
  id: string;
  type: InterfaceType;
};

export default class RemoteDevice {
  protected handle: string;
  protected deviceClass: string;
  protected supportedTypes: string[];
  protected capabilities: DeviceCapabilities[];

  protected ws?: WebSocket;
  protected wss: WebSocketServer;
  protected lws?: WebSocket;
  protected lwss?: WebSocketServer;

  protected subscribed: boolean;
  protected bridge: boolean;
  protected topic_prefix?: string;
  protected node?: AppNode;
  protected interfaceIds?: string[];
  protected properties: Map<string, string>;


  constructor(body: ReqBody, handle: string, wss: WebSocketServer) {
    this.deviceClass = body.deviceClass;
    this.supportedTypes = body.supportedTypes;
    this.handle = handle;
    this.wss = wss;

    this.capabilities = [];
    for (const sType of this.supportedTypes) {
      const capability: DeviceCapabilities = {
        effectType: sType as EffectType,
        state: "stopped",
      };
      this.capabilities.push(capability);
    }

    this.subscribed = false;
    this.bridge = false;
    this.properties = new Map<string, string>();

    console.log("Remote device created with handle:", this.handle);
    wss.on("connection", (ws) => this.onWebSocketConnection(ws));
  }

  protected onWebSocketConnection(ws: WebSocket): void {
    console.log(`${this.handle} connected.`);
    this.ws = ws;

    ws.on("close", () => {
      console.log(`${this.handle} disconnected.`);
      removeRemoteDevice(this.handle);
    });

    ws.on("message", (message) => this.onWebSocketMessage(message));
  }

  protected onWebSocketMessage(message: any): void {
    const msg: string = message.toString();
    console.log(`Client ${this.handle} sent message\n ${msg}\n\n`);

    if (this.bridge) {
      this.sendLocalClientMessage(msg);
      return;
    }

    // Transition Message
    if (msg.includes("transition")) {
      const data: TransitionMetadata = JSON.parse(msg);
      this.publishTransitionMetadata(data);
    }
    // Capabilities Message
    else if (msg.includes("capabilities")) {
      this.onCapabilitiesMessage(msg);
    } else {
      console.error("Message does not have the expected format.");
      return;
    }
  }

  protected sendWebSocketMessage(data: NodeMetadata | ActionMetadata | ControlMetadata) {
    if (this.ws) {
      console.log(`Sendind message to client ${this.handle}\n ${JSON.stringify(data, null, 4)}\n\n`)
      this.ws.send(JSON.stringify(data));
    } else {
      // TODO: store message for later
    }
  }

  protected onCapabilitiesMessage(msg: string): void {
    const data: CapabilitiesMetadata = JSON.parse(msg);

    const newCapability: DeviceCapabilities = this.capabilities.find(
      (c) => c.effectType === data.type
    ) || {
      effectType: data.type as EffectType,
      state: "stopped",
    };

    for (const capability of data.capabilities) {
      if (capability.name === "state") {
        newCapability.state = capability.value;
      } else if (capability.name === "locator") {
        newCapability.locator = capability.value;
      } else if (capability.name === "preparationTime") {
        newCapability.preparationTime = capability.value;
      }
    }

    // Somente um capability por effectType
    this.capabilities = this.capabilities.filter(
      (c) => c.effectType !== newCapability.effectType
    );
    this.capabilities.push(newCapability);

    console.log(
      `Received capabilities for ${this.deviceClass}:`,
      this.capabilities
    );
  }

  protected onMqttMessage(m: string, t?: string): void {
    if (!t) return;

    let topic: string = t.replace(`${this.topic_prefix as string}/`, "");

    try {
      const parsed = this.parseTopic(m, topic);

      if (parsed.eventType == EventType.preparation && m == Action.start) {
        let data: NodeMetadata = {
          nodeId: this.node?.id as string,
          appId: core.app.id as string,
          type: this.node?.mimeType as string,
        };

        if (this.properties.has("src")) {
          data.nodeSrc = this.properties.get("src");
        }

        let props = this.parseProperties();
        if (props.length > 0) {
          data.properties = props;
        }

        this.sendWebSocketMessage(data);
      } else {
        let data: ActionMetadata = {
          nodeId: this.node?.id as string,
          appId: core.app.id as string,
          eventType: parsed.eventType as EventType,
          action: parsed.action as Action,
        };

        if (parsed.label) data.label = parsed.label;

        this.sendWebSocketMessage(data);
      }
    } catch (e) {
      console.error(e);
    }
  }

  protected publishTransitionMetadata(data: TransitionMetadata): void {
    if (!this.subscribed) {
      console.error(`No MQTT topic prefix defined for device ${this.handle}`);
      return;
    }

    let topic = this.topic_prefix;

    if (data.label) topic += `/${data.label}`;
    topic += `/${data.eventType}Event`;
    if (data.eventType == EventType.selection) topic += "/OK";

    mqttClient.publish(topic + "/eventNotification", data.transition, false);

    if (data.user && data.eventType == EventType.selection)
      mqttClient.publish(topic + "/user", data.user);

    if (data.value && data.eventType == EventType.attribution)
      mqttClient.publish(topic + "/value", data.value);
  }

  protected parseTopic(m: string, t: string): Record<string, string> {
    // [:ifaceId/](presentation|preparation|selection|attribution)Event/[:key/]actionNotification

    const parts = t.split("/");
    if (parts.length < 2 || !t.includes("/actionNotification")) {
      throw new Error("Topic does not match expected structure");
    }

    const result: Record<string, string> = {};
    if (parts[0].includes("Event")) {
      // It's the node eventType
      this.parseEvent(parts, m, result);
    } else {
      // must be an interface id
      this.parseInterface(parts, m, result);
    }

    return result;
  }

  protected parseInterface(parts: string[], m: string, result: Record<string, string>): void {
    let part: string = parts.shift() as string;

    if (!this.interfaceIds?.includes(part)) {
      throw new Error(`Unexpected interface id: ${part}`);
    }

    result["label"] = part;

    this.parseEvent(parts, m, result);
  }

  protected parseEvent(parts: string[], m: string, result: Record<string, string>): void {
    let part: string = parts.shift() as string;

    if (!part.includes("Event")) {
      throw new Error(`Should be an event, got ${part} instead`);
    }

    part = part.replace("Event", "");
    if (!Object.values(EventType).includes(part as EventType)) {
      throw new Error(`Event ${part} does not match expected event types`);
    }

    result["eventType"] = part;

    if (part == EventType.selection) {
      // parses the key
      this.parseKey(parts, m, result);
    } else {
      this.parseAction(parts, m, result);
    }
  }

  protected parseKey(parts: string[], m: string, result: Record<string, string>): void {
    let part: string = parts.shift() as string;

    result["key"] = part;

    this.parseAction(parts, m, result);
  }

  protected parseAction(parts: string[], m: string, result: Record<string, string>): void {
    let part: string = parts.shift() as string;

    if (!part.match("actionNotification")) {
      throw new Error(`Expecting actionNotification, got ${parts[0]} instead`);
    }

    if (!Object.values(Action).includes(m as Action)) {
      throw new Error(`Action ${m} does not match expected actions`);
    }

    result["action"] = m;
  }

  public getClass(): string {
    return this.deviceClass;
  }

  public getHandle(): string {
    return this.handle;
  }

  public getSupportedTypes(): string[] {
    return this.supportedTypes;
  }

  public getUrl(): string {
    if (!this.wss) return "";
    return `ws://${core.server.url}:${this.wss.options.port}`;
  }

  public getLocalEntryPointUrl(): string {
    if (!this.lwss) return "";
    return `ws://${core.server.url}:${this.lwss.options.port}`;
  }

  public getCapabilities(): DeviceCapabilities[] {
    if (!this.capabilities) {
      return [];
    }
    return this.capabilities;
  }

  public controlDevice(command: ControlMetadata): void {
    console.log('[RemoteDevice] sending websocket message to SEPE at ', Date.now());
    this.sendWebSocketMessage(command);
  }

  public support(type: string): boolean {
    return this.supportedTypes.includes(type);
  }

  public setNode(node: AppNode): void {
    console.log(`Associating node ${node.id} to device ${this.handle}.`);

    this.node = node;

    this.topic_prefix = mqttClient.parseTopic(TOPICS.app_doc, {
      serviceId: core.app.sid,
      appId: core.app.id,
    });
    let ids = node.id.split(".");
    this.topic_prefix += `/${ids.join("/")}`;

    mqttClient.addTopicHandler(`${this.topic_prefix}/interfaces`, this.setNodeInterfaces.bind(this));

    mqttClient.addTopicHandler(`${this.topic_prefix}/preparationEvent/actionNotification`, this.onMqttMessage.bind(this));
    mqttClient.addTopicHandler(`${this.topic_prefix}/presentationEvent/actionNotification`, this.onMqttMessage.bind(this));

    // mqttClient.addTopicHandler(`${this.topic_prefix}/+/+/actionNotification`, this.onMqttMessage);
    this.subscribed = true;
  }

  public removeNode(): void {
    console.log(`Disassociating node ${this.node?.id} to device ${this.handle}.`);

    mqttClient.removeTopicHandler(`${this.topic_prefix}/interfaces`, this.setNodeInterfaces.bind(this));
    
    mqttClient.removeTopicHandler(`${this.topic_prefix}/preparationEvent/actionNotification`, this.onMqttMessage.bind(this));
    mqttClient.removeTopicHandler(`${this.topic_prefix}/presentationEvent/actionNotification`, this.onMqttMessage.bind(this));

    // mqttClient.removeTopicHandler(`${this.topic_prefix}/+/+/actionNotification`, this.onMqttMessage);
    this.subscribed = false;
    this.node = undefined;
    this.topic_prefix = ''
  }

  protected setNodeInterfaces(interfaces: string): void {
    let ifaces: NodeInterface[] = JSON.parse(interfaces);
    mqttClient.removeTopicHandler(`${this.topic_prefix}/interfaces`, this.setNodeInterfaces.bind(this));

    this.interfaceIds = [];
    this.properties.clear();
    ifaces.forEach((iface) => {
      this.interfaceIds?.push(iface.id);

      if (iface.type == InterfaceType.property) {
        mqttClient.addTopicHandler(`${this.topic_prefix}/${iface.id}/attributionEvent/value`, this.setPropertyValue.bind(this));
      }
    });
  }

  protected setPropertyValue(m: string, t?: string): void {
    if (!t) return;

    // :ifaceId/attributionEvent/value
    let ifaceId: string = t.replace(`${this.topic_prefix as string}/`, "");
    ifaceId = ifaceId.replace("/attributionEvent/value", "");

    this.properties.set(ifaceId, m);

    mqttClient.removeTopicHandler(t, this.setPropertyValue.bind(this));
  }

  protected parseProperties(): PropertiesType {
    let p: PropertiesType = [];
    this.properties.forEach((value, key) => {
      if (key == "src") return;

      p.push({
        name: key,
        value: value,
      });
    });
    return p;
  }

  public addLocalEntryPoint(lwss: WebSocketServer): void {
    this.lwss = lwss;
    lwss.on("connection", (ws) => this.onLocalClientConnection(ws));
  }

  public removeLocalEntryPoint(): void {
    if (this.lws) {
      this.lws.close();
    }
    if (this.lwss) {
      this.lwss.close();
    }
  }

  protected onLocalClientConnection(lws: WebSocket): void {
    console.log(`Local client connected to device ${this.handle}.`);
    this.lws = lws;

    lws.on("close", () => {
      console.log(`Local client disconnected from device ${this.handle}.`);
    });

    lws.on("message", (message) => this.onLocalClientMessage(message));

    this.bridge = true;
  }

  protected onLocalClientMessage(message: any): void {
    const msg: string = message.toString();
    console.log(`Local client sent message\n ${msg}\n\n to device ${this.handle}.`);

    if (this.ws) {
      this.ws?.send(msg);
    }
  }

  protected sendLocalClientMessage(msg: string): void {
    if (this.lws) {
      this.lws.send(msg);
    }
  }

  public terminate(): void {
    if (this.ws) {
      this.ws.close();
    }
    this.wss.close();
    if (this.subscribed) {
      this.removeNode();
    }
    if (this.lws) {
      this.lws.close();
    }
    if (this.lwss) {
      this.lwss.close();
    }
  }
}
