import express, { NextFunction, Request, Response, Router } from 'express';
import { returnError, getClientIP, isLocalClient } from '../util';
const router: Router = express.Router();

router.use((req: Request, res: Response, next: NextFunction) => {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', '*');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, bind-token, Accept, Accept-Version');

    // Default header values
    res.setHeader('API-Version', '2.0');
    res.setHeader('Content-Type', 'application/json');

    // Basic validation
    if (!validateAcceptVersion(req, res)) return;

    // Avoid access validation for authorization API
    if (req.path === '/authorize' || req.path === '/token') {
        return next();
    }

    // Autentication validation
    if (!validateClientProtocol(req, res)) return;

    next();
});

function validateAcceptVersion(req: Request, res: Response): boolean {
    // Check if the client is compatible with current version
    var client_version = req.get('Accept-Version');
    if (client_version !== undefined && client_version !== '2.0') {
        returnError(res, 100);
        return false;
    }
    return true;
}

function validateClientProtocol(req: Request, res: Response): boolean {
    const ip = getClientIP(req);

    // Localhost checks
    if (!isLocalClient(ip) && req.protocol !== 'https') {
        returnError(res, 106);
        return false;
    }
    return true;
}

export default router;