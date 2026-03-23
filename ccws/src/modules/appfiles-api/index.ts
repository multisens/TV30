import express, { Router } from 'express';
import controller from './controller';
const router:Router = express.Router();

/*
    C.6.4.7 Accessing files of a Broadcaster Application
*/
router.get('/:appid/files', controller.GETAppFile);

export default router;