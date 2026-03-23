import * as dotenv from 'dotenv';
import exp from './expression';
import fs from 'fs';
import jsonata from 'jsonata';
import mqttClient, { TOPICS } from '../../mqtt-client';
import path from 'path';
import { Expression, UserAttributes, UsersIdList } from './types';
dotenv.config();


type UserData = {
	currentUser: string,
	currentService: string,
	users: Object
}

type FileData = {
	size: number,
	mime: string,
	name: string,
	file: string
}

const data: UserData = {
	currentUser : '',
	currentService : '',
	users : JSON.parse(fs.readFileSync(process.env.USER_DATA_FILE as string, 'utf-8'))
}


function updateCurrentUser(m: string): void {
	data.currentUser = m;
	console.log(`Set current user ${data.currentUser}.`);
}

mqttClient.addTopicHandler(TOPICS.current_user, updateCurrentUser);


function updateCurrentService(m: string): void {
	data.currentService = m;
	console.log(`Set current service ${data.currentService}.`);
}

mqttClient.addTopicHandler(TOPICS.current_service, updateCurrentService);


function getCurrentUser(): string {
	return data.currentUser;
}

function setCurrentUser(uuid: string): void {
	data.currentUser = uuid;

	mqttClient.publish(TOPICS.current_user, data.currentUser, true);
}

async function getUserList(body: Expression): Promise<UsersIdList> {
	let expression = jsonata(exp.getUsersExpression(body, data.currentService));
	let result = await expression.evaluate(data.users);
	return result;
}

async function getUserAttribute(uuid: string, atname?: string): Promise<UserAttributes> {
	let expression = jsonata(exp.getAttExpression(data.currentService, uuid, atname));
	let result = await expression.evaluate(data.users);
	return result;
}

async function checkConsent(fpath: string): Promise<boolean> {
	let expression = jsonata(exp.getConsentExpression(data.currentService, fpath));
	let result = await expression.evaluate(data.users);
	return result;
}

function getFile(fpath: string): FileData {
	const file_path = path.join(process.env.USER_THUMBS as string, fpath);
	const file_name = path.parse(file_path).base;
	
	const stat = fs.statSync(file_path);
	const file = fs.readFileSync(file_path, 'binary');
	
	return {
		size: stat.size,
		mime: GetMime(path.extname(file_name)),
		name: file_name,
		file: file
	}
}

function GetMime(file_ext: string): string {
	// images
	if (file_ext == '.jpeg' || file_ext == '.jpg') {
		return 'image/jpeg';
	}
	else if (file_ext == '.png') {
		return 'image/png';
	}
	// others
	else {
		return 'application/octet-stream';
	}
}


export default { getCurrentUser, setCurrentUser, getUserList, getUserAttribute, checkConsent, getFile }