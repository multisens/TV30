import * as dotenv from 'dotenv';
dotenv.config();

type LogLevel = 'DEBUG' | 'INFO' | 'ERROR';  // ERROR < INFO < DEBUG
const LOG_LEVEL: LogLevel = (process.env.LOG_LEVEL as LogLevel) || 'ERROR';


function print_log(level: LogLevel, ...args: any[]): void {
    const timestamp = new Date().toISOString();
    console.log(`[${timestamp}] [${level}]`, ...args);
}

const Logger = {
    debug: (...args: any[]): void => {
        if (['DEBUG'].includes(LOG_LEVEL)) {
            print_log(LOG_LEVEL, ...args);
        }
    },
    info: (...args: any[]): void => {
        if (['DEBUG', 'INFO'].includes(LOG_LEVEL)) {
            print_log(LOG_LEVEL, ...args);
        }
    },
    error: (...args: any[]): void => {
        console.error(...args);
    }
};

export default Logger;