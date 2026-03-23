import fs from 'fs';
import core from '../../core';
import path from 'path';


export type FileData = {
	size: number,
	mime: string,
	type: string,
	name: string,
	path: string
}

const MIMES = new Map<string, string>([
	['.mpeg', 'video/mpeg'],
	['.mp4', 'video/mp4'],
	['.mp3', 'audio/mpeg'],
	['.ogg', 'audio/ogg'],
	['.txt', 'text/plain'],
	['.jpeg', 'image/jpeg'],
	['.jpg', 'image/jpeg'],
	['.png', 'image/png'],
	['.obj', 'model/obj']
]);

const TYPES = new Map<string, string>([
	['.mpeg', 'video'],
	['.mp4', 'video'],
	['.mp3', 'audio'],
	['.ogg', 'audio'],
	['.txt', 'text'],
	['.jpeg', 'image'],
	['.jpg', 'image'],
	['.png', 'image'],
	['.obj', 'model']
]);


function validateAppId(appid: string): boolean {
	return appid === core.app.id;
}


function getFile(fpath: string): FileData {
	const file_path = path.join(core.app.url, fpath);
	const file_name = path.parse(file_path).base;
	const file_ext = path.extname(file_name);
	
	const stat = fs.statSync(file_path);
	
	return {
		size: stat.size,
		mime: GetMime(file_ext),
		type: GetType(file_ext),
		name: file_name,
		path: file_path
	}
}


function GetMime(file_ext: string): string {
	if (MIMES.has(file_ext)) {
		return MIMES.get(file_ext) as string;
	}
	else {
		return 'application/octet-stream';
	}
}


function GetType(file_ext: string): string {
	if (TYPES.has(file_ext)) {
		return TYPES.get(file_ext) as string;
	}
	else {
		return 'application';
	}
}

export default { validateAppId, getFile }