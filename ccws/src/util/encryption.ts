import * as crypto from 'crypto';

export function base64UrlEncode(str: Buffer<ArrayBufferLike>): string {
    return str.toString('base64')
        .replace(/\+/g, '-')
        .replace(/\//g, '_')
        .replace(/=/g, '');
}

export function base64UrlDecode(str: string): Buffer<ArrayBufferLike> {
    str = str
        .replace(/-/g, '+')
        .replace(/_/g, '/');
    while (str.length % 4) {
        str += '=';
    }
    return Buffer.from(str, 'base64');
}

export function sha256Encrypt(data: Buffer<ArrayBufferLike>): Buffer<ArrayBufferLike> {
    const hash = crypto.createHash('sha256');
    hash.update(data);
    return hash.digest();
}

export function aes128ECBEncrypt(data: Buffer<ArrayBufferLike>, key: Buffer<ArrayBufferLike>): Buffer<ArrayBufferLike> {
    const cipher = crypto.createCipheriv("aes-128-ecb", key, null);
    cipher.setAutoPadding(true);
    let encrypted = cipher.update(data);
    return Buffer.concat([encrypted, cipher.final()]);
}

export function aes128ECBDecrypt(data: Buffer<ArrayBufferLike>, key: Buffer<ArrayBufferLike>): Buffer<ArrayBufferLike> {
    const decipher = crypto.createDecipheriv('aes-128-ecb', key, null);
    decipher.setAutoPadding(true);
    let decrypted = decipher.update(data);
    return Buffer.concat([decrypted, decipher.final()]);
}

export function createECDHKeys(): [crypto.ECDH, Buffer<ArrayBufferLike>] {
	const privateKey = crypto.createECDH('prime256v1');
	const publicKey = privateKey.generateKeys();
	return [privateKey, publicKey];
}