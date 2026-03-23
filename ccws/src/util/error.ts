import { Response } from 'express';

const Errors: Record<number, string> = {
    [100]: 'API not found',
    [101]: 'Illegal argument value',
    [102]: 'Access not authorized by user',
    [103]: 'Unable to ask for user authorization',
    [104]: 'Access not authorized by the broadcaster',
    [105]: 'Missing argument',
    [106]: 'API unavailable for this runtime environment',
    [107]: 'Invalid or outdated access token',
    [108]: 'Invalid or revoked bind token',

    [200]: 'Platform resource unavailable',
    [201]: 'Format not supported',
    [202]: 'Action not supported',
    [203]: 'Parameter not supported',

    [300]: 'No DTV service currently in use',
    [301]: 'Service information cache unavailable',
    [302]: 'No DTV Signal',
    [303]: 'Empty Application Catalog',
    [304]: 'DTV service not found',
    [305]: 'DTV resource not found',

    [400]: 'Network service unavailable',
    [401]: 'Unsupported or invalid state transition',
    [402]: 'Unsupported or invalid priority transition',
    [403]: 'Unhandled URL scheme',
    [404]: 'URL not found',
    [405]: 'Access to viewer profile information not authorized',
}


export function returnError(res: Response, code: number, full_description?: string) {
    res.status(404).json({
        error: code,
        description: Errors[code],
        full_description: full_description
    });
}