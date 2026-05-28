const ts = () => new Date().toISOString();

export const logInfo = (lbl, msg) => console.log(`${ts()} [${lbl}] ${msg}`);
export const logWarn = (lbl, msg) => console.warn(`${ts()} [${lbl}] WARN: ${msg}`);
export const logErr  = (lbl, msg) => console.error(`${ts()} [${lbl}] ERROR: ${msg}`);
