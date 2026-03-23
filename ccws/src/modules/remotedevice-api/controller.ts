import { Request, Response } from "express";
import service from "./service";

function POSTRemoteDevice(req: Request, res: Response): void {
  const body = req.body;
  if (!body) {
    res.status(400).json({
      error: 106,
      description: "No body defined",
    });
    return;
  }
  let missing: string[] = [];
  if (!body.deviceClass) {
    missing.push("deviceClass");
  }
  if (!body.supportedTypes) {
    missing.push("supportedTypes");
  } else if (body.supportedTypes.length == 0) {
    missing.push("supportedTypes is empty");
  }

  if (missing.length > 0) {
    res.status(400).json({
      error: 105,
      description: `Missing argument: ${missing.join(", ")}`,
    });
    return;
  }
  const response = service.createWebSocket(body);
  res.status(200).json(response);
}

function DELETERemoteDevice(req: Request, res: Response): void {
  const handle = req.params.handle;
  if (!handle) {
    res.status(400).json({
      error: 105,
      description: "Missing argument: handle",
    });
    return;
  }
  if (!service.deleteWebSocket(handle)) {
    res.status(400).json({
      error: 305,
      description: "Handler does not exist",
    });
    return;
  }
  res.status(204).json({});
}

function GETRemoteDevices(req: Request, res: Response): void {
  const classId = req.params["classId"];
  if (!classId) {
    res.status(400).json({
      error: 105,
      description: "Missing argument: classId",
    });
    return;
  }
  const devices = service.getRemoteDevices(classId);
  if (!devices || devices.length === 0) {
    res.status(200).json({});
    return;
  }
  res.status(200).json({
    devices: devices,
  });
}

function GETRemoteDeviceEntryPoint(req: Request, res: Response): void {
  const handle = req.params.handle;
  if (!handle) {
    res.status(400).json({
      error: 105,
      description: "Missing argument: handle",
    });
    return;
  }

  const device = service.getRemoteDevice(handle);
  if (!device) {
    res.status(400).json({
      error: 305,
      description: "Handler does not exist",
    });
    return;
  }
  res.status(200).json(device);
}

function DELETERemoteDeviceEntryPoint(req: Request, res: Response): void {
  const handle = req.params.handle;
  if (!handle) {
    res.status(400).json({
      error: 105,
      description: "Missing argument: handle",
    });
    return;
  }
  if (!service.removeLocalEntryPoint(handle)) {
    res.status(400).json({
      error: 305,
      description: "Handler does not exist",
    });
    return;
  }
  res.status(204).json({});
}

export default { POSTRemoteDevice, DELETERemoteDevice, GETRemoteDevices, GETRemoteDeviceEntryPoint, DELETERemoteDeviceEntryPoint };
