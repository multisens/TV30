module.exports = {
    apps : [
        {
            name        : 'broker',
            script      : '/usr/sbin/mosquitto',
            args        : '-c /mnt/c/Proj_CEFET/GingaDistrib/mosquitto/mosquitto.conf',
            interpreter : 'none',
            wait_ready  : false,
            autorestart : true
        },
        {
            name        : 'aop',
            cwd         : '/mnt/c/Proj_CEFET/GingaDistrib/aop',
            script      : 'npm',
            args        : 'start',
            interpreter : 'none',
            wait_ready  : true,
            autorestart : false,
            env : {
                PORT            : 8080,
                BROKER          : 'mqtt://localhost',
                SCREENWIDTH     : 1440,
                USER_DATA_PATH  : '/mnt/c/Proj_CEFET/GingaDistrib/user-files'
            }
        },
        {
            name        : 'apps',
            cwd         : '/mnt/c/Proj_CEFET/GingaDistrib/apps',
            script      : 'npm',
            args        : 'start',
            interpreter : 'none',
            wait_ready  : true,
            autorestart : false,
            env : {
                PORT            : 8081,
                BROKER          : 'mqtt://localhost',
                USER_DATA_PATH  : '/mnt/c/Proj_CEFET/GingaDistrib/user-files'
            }
        },
        {
            name        : 'tv3ws',
            cwd         : '/mnt/c/Proj_CEFET/GingaDistrib/ccws',
            script      : 'npm',
            args        : 'start',
            interpreter : 'none',
            wait_ready  : true,
            env : {
                PORT            : 44642,
                BROKER          : 'mqtt://localhost',
                SERVER_URL      : 'localhost',
                USER_DATA_FILE  : '/mnt/c/Proj_CEFET/GingaDistrib/user-files/userData.json',
                USER_THUMBS     : '/mnt/c/Proj_CEFET/GingaDistrib/user-files/thumbs'
            }
        }
    ]
}