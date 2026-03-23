import { randomBytes, ECDH } from 'crypto';
import { base64UrlEncode } from '../../util';

export default class Client {
    protected id: string;
    protected refreshToken: string;
    protected challenge?: string;
    protected secret?: Buffer<ArrayBufferLike>;
    protected ECDHKey?: {
        privateKey: ECDH,
        publicKey: Buffer<ArrayBufferLike>
    }
    protected accessToken?: string;

    constructor(id: string) {
        this.id = id;
        this.refreshToken = this.createRefreshToken();
    }

    public getId(): string {
        return this.id;
    }

    public getRefreshToken(): string {
        return this.refreshToken;
    }

    public updateRefreshToken(): string {
        this.refreshToken = this.createRefreshToken();
        return this.refreshToken;
    }

    public validateRefreshToken(refreshToken: string): boolean {
        return this.refreshToken == refreshToken;
    }

    public setChallenge(str: string) {
        this.challenge = str;
    }

    public getChallenge(): string {
        return this.challenge as string;
    }

    public validateChallenge(challenge: string): boolean {
        return this.challenge! == challenge;
    }

    public setSecret(key: Buffer<ArrayBufferLike>) {
        this.secret = key;
    }

    public getSecret(): Buffer<ArrayBufferLike> {
        return this.secret as Buffer<ArrayBufferLike>;
    }

    public setECDHKeys(privateKey: ECDH, publicKey: Buffer<ArrayBufferLike>) {
        this.ECDHKey = {
            privateKey: privateKey,
            publicKey: publicKey
        }
    }

    public getECDHPublicKey(): Buffer<ArrayBufferLike> {
        if (this.ECDHKey === undefined)
            throw Error(`Client ${this.id} has no ECDH key pair.`);

        return this.ECDHKey?.publicKey;
    }

    public setAccessToken(token: string) {
        this.accessToken = token;
    }

    public hasAccessToken(): boolean {
        return this.accessToken !== undefined;
    }

    public getAccessToken(): string {
        return this.accessToken as string;
    }

    protected createRefreshToken(): string {
        return base64UrlEncode(randomBytes(16));
    }
}