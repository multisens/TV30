require('dotenv').config();
const fs = require('fs');
const mqtt = require('mqtt');

const client = mqtt.connect(`mqtt://${process.env.MQTT_HOST}`, {
    clientId : 'aop-core',
    clean : true,
    connectTimeout : 4000,
});

const DATA = {
    rxgui: {
        current: '',
        previous: ''
    },
    graphicsAppURL: '',
    videoStreamURL: '',
    currentUser: '',
    users: [],
    currentService: '',
    serviceList: new Map(),
    serviceMetadata: {}
};

const GUI = {
    app_catalogue: '/appcat',
    profile_chooser: '/prfchs',
    profile_creator: '/prfchs',
    bootstrap_app: '/btpapp'
};

const _t = {
    current_user: 'aop/currentUser',
    current_service: 'aop/currentService',
    lls_metadata: 'tlm/lls/#',
    sls_metadata: 'tlm/sls/+/#',
    gui_layer: 'aop/display/layers/rxgui',
    pmplayer_url : 'aop/display/layers/video/url',
    pmplayer_size : 'aop/display/layers/video/size',
    graphics_layer: 'aop/display/layers/graphics'
};

const _topics = new Map([
    [_t.current_user, loadCurrentUser],
    [_t.current_service, loadCurrentService],
    [_t.lls_metadata, loadLLSMetadata]
]);

client.on('connect', () => {
    console.log('Connected to MQTT broker');
    _topics.forEach((_, key) => {
        client.subscribe(key, { noLocal : true });
    });

    // Additional topics to handle, but no subscribe yet
    _topics.set(_t.sls_metadata, loadSLSMetadata);

    loadUserData();
});

function mqttTopicMatch(topic, filter) {
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
    let found = false;
    _topics.forEach((handler, filter) => {
        if (mqttTopicMatch(topic, filter)) {
            handler(message.toString(), topic);
            found = true;
            return;
        }
    });

    if (!found) {
        console.log(`no handler for topic ${topic}`);
    }
});

function setDisplayGui(screen) {
    client.publish(_t.gui_layer, screen);
    DATA.rxgui.previous = DATA.rxgui.current;
    DATA.rxgui.current = screen;
}

function setDisplayGraphics(baseUrl = '', epUrl = '') {
    DATA.graphicsAppURL = baseUrl;
    client.publish(_t.graphics_layer, baseUrl != '' ? `/graphicsAppProxy${epUrl}` : baseUrl);
}

function setVideoURL(url = '') {
    if (url.endsWith('m3u8') || url.endsWith('mpd')) {
        let file = url.split('/').pop();
        DATA.videoStreamURL = url.replace(`/${file}`, '');
        client.publish(_t.pmplayer_url, `/videoStreamProxy/${file}`);
    }
    else {
        client.publish(_t.pmplayer_url, url);
    }
}

function setVideoSize(top = '0', left = '0', width = '100%', height = '100%') {
    client.publish(_t.pmplayer_size, JSON.stringify({
        top: top,
        left: left,
        width: width,
        height: height
    }));
}

function loadUserData() {
    let userData = JSON.parse(fs.readFileSync(`${process.env.USER_DATA_PATH}/userData.json`));
    userData.users.forEach(usr => {
        DATA.users.push({
            id: usr.id,
            name: usr.name,
            avatar: usr.avatar
        });
    });

    setCurrentUser(DATA.users[0].id);
}

function loadCurrentUser(message) {
    DATA.currentUser = message.toString();
}

function setCurrentUser(uid) {
    DATA.currentUser = uid.toString();
    client.publish(_t.current_user, uid.toString(), { retain : true });
}

function getCurrentUser() {
    return DATA.currentUser;
}

function getUserData(uid) {
    let result = {};
    DATA.users.forEach(usr => {
        if (usr.id == uid) {
            result = usr;
        }
    });
    return result;
}

function getUserList() {
    return DATA.users;
}

function loadCurrentService(message) {
    DATA.currentService = message.toString();
}

function setCurrentService(sid) {
    DATA.currentService = sid.toString();
    client.publish(_t.current_service, sid.toString(), { retain : true });
    client.subscribe(_t.sls_metadata.replace('+', sid), { noLocal : true });
}

function unsetCurrentService() {
    client.unsubscribe(_t.sls_metadata.replace('+', DATA.currentService), { noLocal : true });
    client.publish(_t.current_service, '', { retain : true });
    DATA.currentService = '';
    DATA.serviceMetadata = {};
}

function getCurrentService() {
    return DATA.serviceList.get(DATA.currentService);
}

function loadLLSMetadata(meta, topic) {
    if (!meta || meta == '') {
        DATA.serviceList.clear();
        client.unsubscribe(_t.lls_metadata, { noLocal : true });
        client.subscribe(_t.lls_metadata, { noLocal : true });
        return;
    }

    let lls = topic.split('/').at(-1);
    let t = JSON.parse(meta);
    if (lls == 'bamt') {
        t.forEach(bam => {
            if (DATA.serviceList.has(bam.globalServiceId)) {
                DATA.serviceList.get(bam.globalServiceId).bam = bam;
            }
            else {
                DATA.serviceList.set(bam.globalServiceId, { bam: bam });
            }
        });
    }
}

function getServiceList() {
	return DATA.serviceList;
}

function loadSLSMetadata(meta, topic) {
    let sls = topic.split('/').at(-1);

    if (!meta || meta == '') {
        DATA.serviceMetadata[sls] = undefined;
        if (sls == 'bald') {
            DATA.serviceMetadata.baldHandler = undefined;
        }
        return;
    }

    let t = JSON.parse(meta);
    if (sls == 'esg') {
        DATA.serviceMetadata.esg = t;

        // refresh the bootstrap app if its open
        if (DATA.rxgui.current == GUI.bootstrap_app) {
            setDisplayGui(GUI.bootstrap_app);
        }
    }
    else if (sls == 'bald') {
        DATA.serviceMetadata.bald = t;

        if (DATA.serviceMetadata.baldHandler) {
            DATA.serviceMetadata.baldHandler(t);
        }
    }
}

function getServiceSLS() {
    return DATA.serviceMetadata;
}

function setBALDHandler(handler) {
    DATA.serviceMetadata.baldHandler = handler;
}

function getGraphicsAppURL() {
    return DATA.graphicsAppURL;
}

function getVideoStreamURL() {
    return DATA.videoStreamURL;
}

function openServiceInfo() {
    if (DATA.rxgui.current == '') {
        setDisplayGui(`${GUI.bootstrap_app}?mode=info`);
    }
    if (DATA.graphicsAppURL != '') {
        setDisplayGraphics();
    }
}


module.exports = {
    GUI,
    setDisplayGui,
    setDisplayGraphics,
    setVideoURL,
    setVideoSize,
    setCurrentUser,
    getCurrentUser,
    getUserData,
    getUserList,
    setCurrentService,
    unsetCurrentService,
    getCurrentService,
    getServiceList,
    getServiceSLS,
    setBALDHandler,
    getGraphicsAppURL,
    getVideoStreamURL,
    openServiceInfo
}