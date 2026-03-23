import express, { Application, Request, Response, NextFunction } from "express";

// import middleware
import basic from './middleware/basic';
import authorization from './middleware/authorization';

// import modules routes
import accessAPI from './apis/access';
import dtvAPI from "./modules/dtv-api";
import appfilesAPI from "./modules/appfiles-api";
import userAPI from "./modules/user-api";
import remotedevAPI from "./modules/remotedevice-api";
import sensoryEffectRenderersAPI from "./modules/sensory-effect-renderers-api";

// middleware configuration
const app: Application = express();
app.use(express.json());
app.use(express.urlencoded({ extended: false }));
app.use('/tv3', basic);
app.use('/tv3', authorization);

// routes
app.use("/health", (req: Request, res: Response) => {
  res.status(200).json({
    status: "ok",
    message: "CCWS is running",
  });
});
app.use("/tv3/current-service/apps", appfilesAPI);
app.use("/tv3/current-service/users", userAPI);
app.use("/tv3/remote-device", remotedevAPI);
app.use("/tv3/sensory-effect-renderers", sensoryEffectRenderersAPI);
app.use("/tv3", accessAPI);

export default app;
