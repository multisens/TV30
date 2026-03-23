import express, { Request, Response, Router } from "express";
import controller from "./controller";
const router: Router = express.Router();

/*
    C.6.15.2 Registering a remote device
*/
router.post("/", controller.POSTRemoteDevice);

/*
    C.6.15.3 Deregistering a remote device
*/
router.delete("/:handle", controller.DELETERemoteDevice);

/*
    C.6.15.5 Otaining the list of registered remote devices
        This API allows a local client application to get the list of remote devices
        currently registered with TV 3.0 WebServices in a given class.
*/
router.get("/devices/:classId", controller.GETRemoteDevices);

/*
    C.6.15.6 Activating the communication  with a remote device
        This API allows a local client application to establish communication with
        a remote device.
*/
router.get("/device/:handle", controller.GETRemoteDeviceEntryPoint);

/*
    C.6.15.7 Deactivating the communication  with a remote device
        This API deactivates the communication established between a local client and
        a remote device.
*/
router.delete("/device/:handle", controller.DELETERemoteDeviceEntryPoint);

export default router;
