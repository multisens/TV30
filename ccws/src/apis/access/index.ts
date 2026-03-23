export { pairingMethods } from './service';
import express, { Router } from 'express';
import controller from './controller';
const router: Router = express.Router();


/*
    C.6.1.2 Client authorization
*/
router.get('/authorize', controller.GETAuthorize);


/*
    C.6.1.3 Obtaining the access token
*/
router.get('/token', controller.GETToken);


export default router;