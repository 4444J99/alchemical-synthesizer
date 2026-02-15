let organisms = {};
let socket;
let reconnectInterval = null;

// Color map for all organism/module types
const TYPE_COLORS = {
    "Proteus":      [0, 255, 255],   // Cyan
    "Relinquished": [255, 0, 0],     // Red
    "Golem":        [255, 165, 0],   // Orange
    "Typhon":       [148, 0, 211],   // Violet
    "AgentSmith":   [0, 255, 0],     // Green
    "Ditto":        [255, 255, 0],   // Yellow
    "Subtractive":  [100, 200, 255], // Light blue
    "FM":           [255, 100, 200], // Pink
    "Additive":     [200, 255, 100], // Lime
    "Wavetable":    [255, 200, 100], // Peach
    "PD":           [100, 255, 200], // Mint
    "Physical":     [200, 150, 100], // Tan
    "WestCoast":    [255, 100, 100], // Coral
    "Formant":      [180, 100, 255], // Lavender
    "Vector":       [100, 180, 255], // Sky
    "Granular":     [220, 220, 220]  // Silver
};

function setup() {
    createCanvas(windowWidth, windowHeight);
    background(0);
    connectWebSocket();
}

function connectWebSocket() {
    socket = new WebSocket(`ws://${window.location.host}`);

    socket.onopen = () => {
        if (reconnectInterval) {
            clearInterval(reconnectInterval);
            reconnectInterval = null;
        }
    };

    socket.onmessage = (event) => {
        let msg = JSON.parse(event.data);
        handleOsc(msg);
    };

    socket.onclose = () => {
        // Auto-reconnect every 3 seconds
        if (!reconnectInterval) {
            reconnectInterval = setInterval(() => {
                connectWebSocket();
            }, 3000);
        }
    };

    socket.onerror = () => {
        socket.close();
    };
}

function handleOsc(msg) {
    if (msg.address === "/brahma/organism/update") {
        let id = msg.args[0].value;
        organisms[id] = {
            type: msg.args[1].value,
            coherence: msg.args[2].value,
            entropy: msg.args[3].value,
            lastUpdate: millis()
        };
    }
}

function getTypeColor(type) {
    return TYPE_COLORS[type] || [255, 255, 255]; // Default white
}

function draw() {
    background(0, 20); // Trails

    translate(width / 2, height / 2);

    let count = 0;
    for (let id in organisms) {
        let org = organisms[id];
        let age = millis() - org.lastUpdate;

        if (age > 2000) {
            delete organisms[id];
            continue;
        }

        // Visual mapping
        let r = map(org.coherence, 0, 1, 50, 200);
        let jitter = map(org.entropy, 0, 10, 0, 10);

        // Position offset so multiple organisms don't overlap
        let angleOffset = count * (TWO_PI / Math.max(Object.keys(organisms).length, 1));
        let cx = cos(angleOffset) * 120;
        let cy = sin(angleOffset) * 120;

        push();
        translate(cx, cy);

        noFill();
        strokeWeight(2);

        let col = getTypeColor(org.type);
        let alpha = map(age, 0, 2000, 200, 0);
        stroke(col[0], col[1], col[2], alpha);

        beginShape();
        for (let i = 0; i < TWO_PI; i += 0.1) {
            let offset = map(noise(i + millis() * 0.001 + count), 0, 1, -jitter, jitter);
            let x = (r + offset) * cos(i);
            let y = (r + offset) * sin(i);
            vertex(x, y);
        }
        endShape(CLOSE);

        fill(col[0], col[1], col[2], alpha);
        noStroke();
        textAlign(CENTER);
        text(`${org.type} [${id}]`, 0, -r - 10);

        pop();
        count++;
    }
}

function windowResized() {
    resizeCanvas(windowWidth, windowHeight);
}
