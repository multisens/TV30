import core from "../../core";
import mqttClient, { TOPICS } from "../../mqtt-client";
import { ReqBody } from "../remotedevice-api/service";
import RemoteDevice, { AppNode } from "./remote-device";
import { WebSocketServer } from "ws";
import { CapabilitiesMetadata } from "./types";

const devices = new Map<string, RemoteDevice>();
const devclasses = new Map<string, string[]>();

function associateAppNodes() {
  let nodes: AppNode[] = core.app.nodes;
  nodes.forEach((node) => {
    if (devices.has(node.device)) {
      if (devices.get(node.device)?.support(node.mimeType)) {
        devices.get(node.device)?.setNode(node);
      }
    }
  });
}

function disassociateAppNodes() {
  devices.forEach((dev) => {
    dev.removeNode();
  });
}

function addRemoteDevice(body: ReqBody, handle: string, wss: WebSocketServer): RemoteDevice {
  let device = new RemoteDevice(body, handle, wss);
  devices.set(handle, device);

  let devclass = device.getClass();
  if (devclasses.has(devclass)) {
    devclasses.get(devclass)?.push(device.getHandle());
  } else {
    devclasses.set(devclass, [device.getHandle()]);
  }

  mqttClient.publish(`${TOPICS.devices}/${devclass}`, JSON.stringify(devclasses.get(devclass)), true);

  return device;
}

function removeRemoteDevice(handle: string): boolean {
  if (!devices.has(handle)) return false;

  const dev = devices.get(handle);
  let devclass = dev?.getClass() as string;
  dev?.terminate();

  devices.delete(handle);
  let handles: string[] = devclasses.get(devclass) as string[];
  devclasses.set(devclass, handles.filter(h => h !== handle));
  console.log(`Client ${handle} unregistered.`);

  let content = '';
  handles = devclasses.get(devclass) as string[];
  if (handles.length > 0) {
    content = JSON.stringify(handles);
  }
  mqttClient.publish(`${TOPICS.devices}/${devclass}`, content, true);
  return true;
}

function getDevicesByClass(classId: string): RemoteDevice[] {
  if (!devclasses.has(classId)) return [];

  let handles = devclasses.get(classId);
  if (!handles) return [];

  let result: RemoteDevice[] = [];
  handles.forEach((handle) => {
    if (devices.has(handle)) {
      result.push(devices.get(handle)!);
    }
  });

  return result;
}

function getDeviceByHandle(handle: string): RemoteDevice | undefined {
  if (!devices.has(handle)) return undefined;
  return devices.get(handle);
}

// Allows SEPE to request the capabilities of a device whenever it needs
function requestDeviceCapabilities(handle: string): CapabilitiesMetadata[] {
  const device = devices.get(handle);
  if (!device) throw new Error(`Device with handle ${handle} not found`);

  const deviceCapabilities = device.getCapabilities();

  const result = deviceCapabilities.map((capability) => {
    return {
      type: capability.effectType,
      capabilities: [
        { name: "state", value: capability.state },
        { name: "locator", value: capability.locator },
        {
          name: "preparationTime",
          value: capability.preparationTime,
        },
      ],
    };
  });

  return result as CapabilitiesMetadata[];
}

export {
  associateAppNodes,
  disassociateAppNodes,
  addRemoteDevice,
  removeRemoteDevice,
  getDevicesByClass,
  getDeviceByHandle,
  requestDeviceCapabilities,
};
