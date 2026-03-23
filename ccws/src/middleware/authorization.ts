import express, { NextFunction, Request, Response, Router } from 'express';
import * as manager from '../modules/auth-manager/manager';
import { returnError, getClientIP, isLocalClient } from '../util';
const router: Router = express.Router();

router.use((req: Request, res: Response, next: NextFunction) => {
    // Avoid access validation for authorization API
    if (req.path === '/authorize' || isLocalClient(getClientIP(req))) {
        return next();
    }

    // Autentication validation
    if (!validateAccess(req, res)) return;

    next();
});


function validateAccess(req: Request, res: Response): boolean {
    var token = req.get('Authorization');
    if (token === undefined ) {
        returnError(res, 107);
        return false;
    }
    if (!manager.validateAccessToken(token as string)) {
        returnError(res, 107);
        return false;
    }
    return true;
}

export default router;