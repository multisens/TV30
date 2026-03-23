import express, { Router } from "express";
import controller from "./controller";
const router: Router = express.Router();

/*
    C.6.16.1 Obtaining the available sensory effect renderers
*/
router.get("/", controller.GETRenderers);

/*
    C.6.16.2 Obtaining the information about a specific sensory effect renderer
*/
router.get("/:rendererId", controller.GETRenderer);

/*
   C.6.16.3 Controlling a specific sensory effect renderer 
*/
router.post("/:rendererId", controller.POSTControlRenderer);

export default router;
