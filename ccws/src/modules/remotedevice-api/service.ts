import http from "http";
import { v4 as uuidv4 } from "uuid";
import { WebSocketServer } from "ws";
import * as manager from "../remotedevice-manager/manager";
import { Device } from "./types";

export type ReqBody = {
  deviceClass: string;
  supportedTypes: string[];
};

export type Response = {
  handle: string;
  url?: string;
};

export type DeviceResponse = {
  url: string;
};

function createWebSocket(body: ReqBody): Response {
  const server = http.createServer();
  const wsServer = new WebSocketServer({ server });
  const port = generateDynamicallyPort();
  const uuid = uuidv4();

  server.listen(port, () => {
    console.log(`WebSocket server is running on port ${port}`);
  });
  wsServer.options.port = port;

  const device = manager.addRemoteDevice(body, uuid, wsServer);
  console.log(`Client ${device.getHandle()} registered.`);

  return {
    handle: device.getHandle(),
    url: device.getUrl(),
  };
}

function generateDynamicallyPort(): number {
  return Math.floor(1000 + Math.random() * 9000);
}

function deleteWebSocket(handle: string): boolean {
  return manager.removeRemoteDevice(handle);
}

function getRemoteDevices(classId: string): Device[] | undefined {
  const devices = manager.getDevicesByClass(classId);
  if (!devices) return undefined;

  return devices.map((device) => ({
    handle: device.getHandle(),
    supportedTypes: device.getSupportedTypes()
  }));
}

function getRemoteDevice(handle: string): DeviceResponse | undefined {
  const device = manager.getDeviceByHandle(handle);
  if (!device) return undefined;

  const server = http.createServer();
  const wsServer = new WebSocketServer({ server });
  const port = generateDynamicallyPort();

  server.listen(port, () => {
    console.log(`WebSocket server is running on port ${port}`);
  });
  wsServer.options.port = port;

  device.addLocalEntryPoint(wsServer);
  return {
    url: device.getLocalEntryPointUrl(),
  };
}

function removeLocalEntryPoint(handle: string): boolean {
  const device = manager.getDeviceByHandle(handle);
  if (!device) return false;

  device.removeLocalEntryPoint();
  return true;
}

export default { createWebSocket, deleteWebSocket, getRemoteDevices, getRemoteDevice, removeLocalEntryPoint };
