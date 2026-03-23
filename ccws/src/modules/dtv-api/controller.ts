import { Request, Response } from 'express';
import core from '../../core';
import { v4 as uuidv4 } from 'uuid';


function GETAuthorize(req: Request, res: Response): void {
	res.status(200).json({
		challenge : uuidv4()
	});
}

function GETToken(req: Request, res: Response): void {
	res.status(200).json({
		accessToken : uuidv4(),
		tokenType : "uuidv4",
		expiresIn : 100000,
		refreshToken : uuidv4(),
		serverCert : uuidv4()
	});
}

function GETCurrentService(req: Request, res: Response): void {
	res.status(200).json({
		serviceContextId : core.current.serviceContextId,
		serviceName : core.current.serviceName,
		transportStreamId : core.current.transportStreamId,
		originalNetworkId : core.current.originalNetworkId,
		serviceId : String(core.current.serviceId)
	});
}


export default { GETAuthorize, GETToken, GETCurrentService }