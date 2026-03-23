import * as dotenv from "dotenv";
import os from 'os';
import logger from './logger';
import mqttClient, { TOPICS, client } from "./mqtt-client";
import { AppNode } from "./modules/remotedevice-manager/remote-device";
import { associateAppNodes, disassociateAppNodes } from "./modules/remotedevice-manager/manager";
dotenv.config();

type CoreData = {
  server: {
    url: string;
    localIP: string;
  };
  app: {
    sid: string;
    id: string;
    url: string;
    nodes: AppNode[];
  };
  services: {
    serviceId: number;
    serviceName: string;
    serviceIcon: string;
    initialMediaURL: string;
  }[];
  current: {
    serviceName: string;
    serviceId: number;
    serviceContextId: string;
    transportStreamId: string;
    originalNetworkId: string;
  };
};

const data: CoreData = {
  server: {
    url: process.env.SERVER_URL as string,
    localIP: getLocalIP()
  },
  app: {
    sid: "",
    id: "",
    url: "",
    nodes: [],
  },
  services: [],
  current: {
    serviceName: "",
    serviceId: -1,
    serviceContextId: "c08b2c72-fd14-4095-adaf-2e5810850c57",
    transportStreamId: "c08b2c72-fd14-4095-adaf-2e5810850c57",
    originalNetworkId: "09e59a1d-e2e7-467e-85db-2fb5a572e2fc",
  },
};

function getLocalIP(): string {
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

function setAppId(appid: string): void {
  if (!appid) return;
  if (data.app.id == appid) return;

  if (data.app.sid && data.app.id) {
    let t = mqttClient.parseTopic(TOPICS.app_path, {
      serviceId: data.app.sid,
      appId: data.app.id,
    });
    mqttClient.removeTopicHandler(t, setAppBaseURL);

    t = mqttClient.parseTopic(TOPICS.app_nodes, {
      serviceId: data.app.sid,
      appId: data.app.id,
    });
    mqttClient.removeTopicHandler(t, setAppNodes);
  }

  if (appid) {
    let t = mqttClient.parseTopic(TOPICS.app_path, {
      serviceId: data.app.sid,
      appId: appid,
    });
    mqttClient.addTopicHandler(t, setAppBaseURL);

    t = mqttClient.parseTopic(TOPICS.app_nodes, {
      serviceId: data.app.sid,
      appId: appid,
    });
    mqttClient.addTopicHandler(t, setAppNodes);
  }

  data.app.id = appid;
}

function setAppBaseURL(path: string): void {
  if (!path) return;

  data.app.url = path;
}

function setAppNodes(nodes: string) {
  if (nodes) {
    data.app.nodes = JSON.parse(nodes);
    associateAppNodes();
  }
  else {
    disassociateAppNodes();
  }
}

function currentService(sid: string): void {
  if (sid == data.app.sid) return;

  if (data.app.sid && data.app.id) {
    let t = mqttClient.parseTopic(TOPICS.current_app, {
      serviceId: data.app.sid,
    });
    mqttClient.removeTopicHandler(t, setAppId);

    if (data.app.id) {
      let t = mqttClient.parseTopic(TOPICS.app_path, {
        serviceId: data.app.sid,
        appId: data.app.id,
      });
      mqttClient.removeTopicHandler(t, setAppBaseURL);

      t = mqttClient.parseTopic(TOPICS.app_nodes, {
        serviceId: data.app.sid,
        appId: data.app.id,
      });
      mqttClient.removeTopicHandler(t, setAppNodes);
    }
  }
  if (sid) {
    let t = mqttClient.parseTopic(TOPICS.current_app, { serviceId: sid });
    mqttClient.addTopicHandler(t, setAppId);
  }

  data.app.sid = sid;
  data.app.id = "";
  data.app.url = "";
  data.app.nodes = [];
  data.current.serviceId = data.services[Number(sid)]?.serviceId;
  data.current.serviceName = data.services[Number(sid)]?.serviceName;
}

mqttClient.addTopicHandler(TOPICS.current_service, currentService);

function loadServiceData(m: string): void {
  if (!m) return;

  data.services = JSON.parse(m);
}

mqttClient.addTopicHandler(TOPICS.services, loadServiceData);

const _t = {
    yesno_popup: 'aop/display/layers/popup/yesno',
    qrcode_popup: 'aop/display/layers/popup/qrcode',
    pin_popup: 'aop/display/layers/popup/pin',
};

type subscribeFunction = (m: string, t: string) => void;
const _topics: Map<string, subscribeFunction> = new Map([
    // [_t.yesno_popup, yesNoPopUpResponse]
]);

function subscribeToTopicList() {
    _topics.forEach((_, key) => {
        client.subscribe(key, { qos : 1, nl : true });
        logger.debug(`Subscribed to topic ${key} at startup`);
    });
}

function subscribe(topic: string, callback: subscribeFunction): void {
    _topics.set(topic, callback);
    client.subscribe(topic, { qos : 1, nl : true });
    logger.debug(`Subscribed to topic ${topic}`);
}

function unsubscribe(topic: string) {
    _topics.delete(topic);
    client.unsubscribe(topic);
    logger.debug(`Unsubscribed from topic ${topic}`);
}

function mqttTopicMatch(topic: string, filter: string): boolean {
    let filterregex = filter.split('/').map(level => {
        if (level === '+') {
            return '[^/#+]+';
        } else if (level === '#') {
            return '.*';
        } else {
            return level.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
        }
    }).join('/');

    let regex = new RegExp(`^${filterregex}$`);
    return regex.test(topic);
}

client.on('message', (topic, message) => {
    logger.debug(`Received message ${message.toString()} in topic ${topic}`);
    
    let found = false;
    _topics.forEach((handler, filter) => {
        if (mqttTopicMatch(topic, filter)) {
            handler(message.toString(), topic);
            found = true;
            return;
        }
    });

    if (!found) {
        logger.debug(`No handler for topic ${topic}`);
    }
});

export function showYesNoPopUpAsync(message: string, timeout: number = 1000): Promise<boolean> {
    logger.info(`Calling Yes/No popup with message:\n${message}\nTimeout in ${timeout}ms`);
    const messageTopic = _t.yesno_popup + '/message';
    const responseTopic = _t.yesno_popup + '/response';

    return new Promise((resolve) => {
        const wrapup = (b: boolean) => {
            unsubscribe(responseTopic);
            resolve(b);
        }
        
        const timeoutId = setTimeout(() => {
            logger.debug('Timeout for popup');
            wrapup(false);
        }, timeout);
        
        const callback: subscribeFunction = (m: string, _) => {
            logger.debug(`Received response ${m} for Yes/No popup`);
            clearTimeout(timeoutId);
            wrapup(Boolean(m));
        };
        subscribe(responseTopic, callback);
        const msg = JSON.stringify({ value: message, timeout: timeout });
        client.publish(messageTopic, msg);
    });
}

export function showQRCodePopUp(code: string, timeout: number) {
    logger.info(`Calling QRCode popup with code:\n${code}\nTimeout in ${timeout}ms`);
    const msg = JSON.stringify({ value: code, timeout: timeout });
    client.publish(_t.qrcode_popup, msg);
}

export function showPINPopUp(pin: string, timeout: number) {
    logger.info(`Calling PIN popup with pin:\n${pin}\nTimeout in ${timeout}ms`);
    const msg = JSON.stringify({ value: pin, timeout: timeout });
    client.publish(_t.pin_popup, msg);
}

export default data;
