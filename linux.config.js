module.exports = {
    apps : [
        {
            name        : 'broker',
            script      : '/usr/bin/mosquitto',
            args        : '-c ./mosquitto/mosquitto.conf',
            interpreter : 'none',
            wait_ready  : true,
            autorestart : false
        },
        {
            name        : 'aop',
            cwd         : './aop',
            script      : 'npm',
            args        : 'start',
            interpreter : 'none',
            wait_ready  : true,
            autorestart : false,
            env : {
                PORT            : 8080,
                BROKER          : 'mqtt://localhost',
                SCREENWIDTH     : 1440,
                USER_DATA_PATH  : '../user-files'
            }
        },
        {
            name: 'apps',
            cwd: './apps',
            interpreter: "none",
            script: "/bin/bash",
            args: '-c "npm run build && npm start"',
            wait_ready: true,
            autorestart: false,
            env: {
                PORT: 8081,
                HOST_IP: '192.168.1.21',
                BROKER: 'mqtt://localhost',
                USER_DATA_PATH: '../user-files'
            }
        },
        {
            name: 'tv3ws',
            cwd: './ccws',
            interpreter: "none",
            script: "/bin/bash",
            args: '-c "npm run build && npm start"',
            wait_ready: true,
            env: {
                PORT: 44642,
                BROKER: 'mqtt://localhost',
                SERVER_URL: 'localhost',
                USER_DATA_FILE: '../user-files/userData.json',
                USER_THUMBS: '../user-files/thumbs'
            }
        },
        {
            name: "chrome-topic-explorer",
            interpreter: "/bin/bash",
            autorestart: false,
            script: "./start-chrome.sh",
            args: "./mqtt-explorer/index.html",
        },
        {
            name: "chrome-aop",
            interpreter: "/bin/bash",
            autorestart: false,
            script: "./start-chrome.sh",
            args: "http://localhost:8080",
        },
        {
            name: "eduplay",
            cwd: "./eduplay",
            interpreter: "none",
            script: "/bin/bash",
            args: '-c "npm run build && npm start"',
            wait_ready: true,
        },
        {
            name: "sepe",
            cwd: "./sepe",
            interpreter: "none",
            script: "/bin/bash",
            args: '-c "npm run build && npm start"',
            wait_ready: true,
        }
    ]
}