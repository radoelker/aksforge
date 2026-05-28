// Structured JSON logger — outputs to stdout for Loki/Alloy collection (Step 13)
// Format matches the handoff spec so Grafana dashboards can filter by field directly.

type LogLevel = 'info' | 'warn' | 'error';
type LogEvent = 'request_success' | 'request_error' | 'db_write' | 'db_read' | 'startup' | 'shutdown';

interface LogEntry {
    timestamp: string;
    level: LogLevel;
    event: LogEvent;
    route?: string;
    duration_ms?: number;
    status_code?: number;
    error_message?: string | null;
    [key: string]: unknown;   // allow extra fields without breaking the type
}

function writeLog(entry: LogEntry): void {
    // process.stdout.write is preferred over console.log —
    // avoids the extra newline formatting and keeps output clean for log collectors
    process.stdout.write(JSON.stringify(entry) + '\n');
}

export const logger = {
    info(event: LogEvent, fields: Omit<LogEntry, 'timestamp' | 'level' | 'event'> = {}): void {
        writeLog({ timestamp: new Date().toISOString(), level: 'info', event, ...fields });
    },

    warn(event: LogEvent, fields: Omit<LogEntry, 'timestamp' | 'level' | 'event'> = {}): void {
        writeLog({ timestamp: new Date().toISOString(), level: 'warn', event, ...fields });
    },

    error(event: LogEvent, fields: Omit<LogEntry, 'timestamp' | 'level' | 'event'> = {}): void {
        writeLog({ timestamp: new Date().toISOString(), level: 'error', event, ...fields });
    },
};