import express, { Router } from 'express';
import controller from './controller';
const router: Router = express.Router();

/*
    C.6.14.1 Obtaining a list of user ids
*/
router.post('/', controller.POSTUserList);

/*
    C.6.14.3 Obtaining the current user
*/
router.get('/current-user', controller.GETCurrentUser);

/*
    C.6.14.4 Changing the current user
*/
router.post('/current-user', controller.POSTCurrentUser);

/*
    C.6.14.6 Obtaining a user file content
*/
router.get('/files', controller.GETUserFile);

/*
    C.6.14.2 Obtaining a set of user attributes
*/
router.get('/:userid', controller.GETUserAttribute);

export default router