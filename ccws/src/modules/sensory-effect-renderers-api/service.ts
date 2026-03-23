import {
  getDeviceByHandle,
  getDevicesByClass,
} from "../remotedevice-manager/manager";
import { ControlMetadata } from "../remotedevice-manager/types";

function getRenderersMetadata() {
  const sensoryDevices = getDevicesByClass("sensory-effect");
  const renderers = sensoryDevices.map((device) => {
    return {
      id: device.getHandle(),
      supportedTypes: device.getSupportedTypes(),
      capabilities: device.getCapabilities(),
    };
  });

  return renderers;
}

function getRendererMetadata(rendererId: string) {
  const renderer = getDeviceByHandle(rendererId);

  if (!renderer || renderer.getClass() !== "sensory-effect") {
    return undefined;
  }

  return {
    id: renderer.getHandle(),
    supportedTypes: renderer.getSupportedTypes(),
    capabilities: renderer.getCapabilities(),
  };
}

function controlRenderer(rendererId: string, body: ControlMetadata) {
  const renderer = getDeviceByHandle(rendererId);
  if (!renderer || renderer.getClass() !== "sensory-effect") {
    throw new Error("Invalid renderer-id, renderer not found");
  }

  if (!body || !body.effectType || !body.action) {
    throw new Error("Invalid body, effectType and action are required");
  }

  if (!renderer.support(body.effectType)) {
    throw new Error(
      `Renderer does not support effect type: ${body.effectType}`
    );
  }

  const action = body.action;
  const properties = body.properties || [];

  renderer.controlDevice({
    effectType: body.effectType,
    action: action,
    properties: properties.map((prop) => ({
      name: prop.name,
      value: prop.value,
    })),
  });
}

export default {
  getRenderersMetadata,
  getRendererMetadata,
  controlRenderer,
};
