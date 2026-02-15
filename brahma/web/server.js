const osc = require("osc");
const WebSocket = require("ws");
const express = require("express");
const path = require("path");

const HTTP_PORT = 3000;
const OSC_UDP_PORT = 57122; // Listening for SC
const OSC_SEND_PORT = 57120; // Sending to SC

// Namespace whitelist: all OSC address prefixes allowed from browser → SC
const ALLOWED_NAMESPACES = [
    "/golem/", "/brahma/", "/chronos/", "/daemon/",
    "/moirai/", "/genesis/", "/arbor/", "/serpens/",
    "/scriptorium/"
];

// Module registry cache (populated from SC broadcasts)
const moduleCache = {};
const paramCache = {};

// 1. HTTP Server
const app = express();
app.use(express.static(path.join(__dirname, "public")));
app.use("/golem", express.static(path.join(__dirname, "public", "golem")));
app.use("/cortex", express.static(path.join(__dirname, "public", "cortex")));

// REST API: module registry
app.get("/api/modules", (req, res) => {
    res.json(Object.values(moduleCache));
});

app.get("/api/modules/:name/params", (req, res) => {
    const params = paramCache[req.params.name] || [];
    res.json(params);
});

const server = app.listen(HTTP_PORT, () => {
    console.log(`--- VISUAL CORTEX ONLINE: http://localhost:${HTTP_PORT} ---`);
    console.log(`--- GOLEM UI: http://localhost:${HTTP_PORT}/golem ---`);
    console.log(`--- CORTEX UI: http://localhost:${HTTP_PORT}/cortex ---`);
});

// 2. WebSocket Server (for Browser)
const wss = new WebSocket.Server({ server });

// 3. OSC UDP Port (From SuperCollider)
const udpPort = new osc.UDPPort({
    localAddress: "0.0.0.0",
    localPort: OSC_UDP_PORT,
    metadata: true
});

// 4. OSC Send Port (To SuperCollider)
const sendPort = new osc.UDPPort({
    localAddress: "0.0.0.0",
    localPort: 0, // ephemeral
    remoteAddress: "127.0.0.1",
    remotePort: OSC_SEND_PORT,
    metadata: true
});

wss.on("connection", (ws) => {
    console.log("Client Connected to Visual Cortex");

    ws.on("message", (message) => {
        try {
            const msg = JSON.parse(message);

            // Forward allowed namespace messages from browser to SC via OSC
            if (msg.address && ALLOWED_NAMESPACES.some(ns => msg.address.startsWith(ns))) {
                const oscArgs = (msg.args || []).map(arg => {
                    if (typeof arg === "number") {
                        return Number.isInteger(arg)
                            ? { type: "i", value: arg }
                            : { type: "f", value: arg };
                    }
                    return { type: "s", value: String(arg) };
                });

                sendPort.send({
                    address: msg.address,
                    args: oscArgs
                });
            }
        } catch (e) {
            // Ignore malformed messages
        }
    });
});

// Broadcast incoming OSC to all WebSocket clients + cache registry data
udpPort.on("message", (oscMsg) => {
    // Cache registry module broadcasts
    if (oscMsg.address === "/brahma/registry/module") {
        const name = oscMsg.args[0]?.value;
        if (name) {
            moduleCache[name] = {
                name: name,
                category: oscMsg.args[1]?.value || "",
                synthDef: oscMsg.args[2]?.value || "",
                numParams: oscMsg.args[3]?.value || 0,
                numInstances: oscMsg.args[4]?.value || 0,
                description: oscMsg.args[5]?.value || ""
            };
        }
    }

    // Cache registry param broadcasts
    if (oscMsg.address === "/brahma/registry/param") {
        const moduleName = oscMsg.args[0]?.value;
        const paramName = oscMsg.args[1]?.value;
        if (moduleName && paramName) {
            if (!paramCache[moduleName]) paramCache[moduleName] = [];
            // Avoid duplicates
            const existing = paramCache[moduleName].findIndex(p => p.name === paramName);
            const param = {
                name: paramName,
                default: oscMsg.args[2]?.value || 0,
                min: oscMsg.args[3]?.value || 0,
                max: oscMsg.args[4]?.value || 1,
                units: oscMsg.args[5]?.value || "",
                desc: oscMsg.args[6]?.value || ""
            };
            if (existing >= 0) {
                paramCache[moduleName][existing] = param;
            } else {
                paramCache[moduleName].push(param);
            }
        }
    }

    // Broadcast to all WebSocket clients
    const jsonMsg = JSON.stringify({
        address: oscMsg.address,
        args: oscMsg.args
    });

    wss.clients.forEach(client => {
        if (client.readyState === WebSocket.OPEN) {
            client.send(jsonMsg);
        }
    });
});

udpPort.on("ready", () => {
    console.log(`OSC Listener Ready on port ${OSC_UDP_PORT}`);
});

sendPort.on("ready", () => {
    console.log(`OSC Sender Ready -> port ${OSC_SEND_PORT}`);
});

udpPort.open();
sendPort.open();
