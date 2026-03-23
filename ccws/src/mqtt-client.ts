import * as dotenv from 'dotenv';
import mqtt, { MqttClient } from 'mqtt';
dotenv.config();

let brokerUrl: string = process.env.MQTT_HOST || 'localhost';
export const client: MqttClient = mqtt.connect(`mqtt://${brokerUrl}`, {
    clientId : 'tv3ws-client',
    clean : true,
    connectTimeout : 4000,
    protocolVersion: 5
});


export const TOPICS = {
    users: 'aop/users',
    current_user: 'aop/currentUser',
    services: 'aop/services',
    current_service: 'aop/currentService',
    current_app: 'aop/:serviceId/currentApp',
    app_path: 'aop/:serviceId/:appId/path',
    app_nodes: 'aop/:serviceId/:appId/doc/nodes',
    app_doc: 'aop/:serviceId/:appId/doc',
    devices: 'aop/devices'
}

type TopicHandler = {
    (m: string, t?: string): void;
};
const TOPIC_HANDLER = new Map<string, TopicHandler[]>();


client.on('connect', () => {
    console.log('Connected to MQTT broker');
});

client.on('message', (topic, message) => {
    console.log(`Message received in ${topic}: ${message.toString()}`);

    if (TOPIC_HANDLER.has(topic)) {
        TOPIC_HANDLER.get(topic)?.forEach(f => {
            f(message.toString(), topic);
        });
    }
    else {
        console.log(`no handler for topic ${topic}`);
    }
});


function addTopicHandler(t: string, f: TopicHandler): void {
    if (TOPIC_HANDLER.has(t)) {
        TOPIC_HANDLER.get(t)?.push(f);
        console.log(`Added handler to topic ${t}`);
    }
    else {
        TOPIC_HANDLER.set(t, [f]);
        client.subscribe(t, { qos : 1, nl : true }); 
        console.log(`Subscribed handler to topic ${t}`);
    }
}

function removeTopicHandler(t: string, f: TopicHandler): void {
    if (!TOPIC_HANDLER.has(t)) {
        console.log(`Topic ${t} not found in handlers`);
        return;
    }

    let handlers = TOPIC_HANDLER.get(t)!;
    let index = handlers.findIndex(handler => handler.toString() === f.toString());
    
    if (index === -1) {
        console.log(`Handler not found for topic ${t}`);
        return;
    }

    handlers.splice(index, 1);

    if (handlers.length === 0) {
        TOPIC_HANDLER.delete(t);
        client.unsubscribe(t);
        console.log(`Unsubscribed from topic ${t} (no more handlers)`);
    } else {
        TOPIC_HANDLER.set(t, handlers);
        console.log(`Handler removed from topic ${t}, ${handlers.length} remaining`);
    }
}

function publish(t: string, m: string, r: boolean = true): void {
    client.publish(t, m, { retain : r });
}


function parseTopic(topic: string, params: Record<string, string>): string {
    let parts = topic.split('/');
    for (let i = 0; i < parts.length; i++) {
        if (parts[i].startsWith(':')) {
            let key = parts[i].substring(1);
            if (key in params) {
                parts[i] = params[key];
            }
        }
    }

    return parts.join('/');
}


export default { addTopicHandler, removeTopicHandler, publish, parseTopic }