import { Request } from 'express';
import os from 'os';

export function getLocalIP(): string {
    const interfaces = os.networkInterfaces();

    for (const name of Object.keys(interfaces)) {
      const ifaceList = interfaces[name];
      if (!ifaceList) continue;

      for (const iface of ifaceList) {
        if (iface.family === 'IPv4' && !iface.internal) {
          return iface.address;
        }
      }
    }
    return '127.0.0.1';
}

function findIPinReq(req: Request): string {
    var aux = req.get('x-forwarded-for');
    if (aux) {
        var ips = (aux as string).split(',');
        return ips[0].trim();
    }

    aux = req.get('x-real-ip');
    if (aux) {
        return aux as string;
    }

    return req.socket.remoteAddress || req.ip || '0.0.0.0';
}

export function getClientIP(req: Request): string {
    return findIPinReq(req).replace(/^::ffff:/, '');
}

export function isLocalClient(ip: string): boolean {
    return ['127.0.0.1', '::1', 'localhost', getLocalIP()].includes(ip);
}