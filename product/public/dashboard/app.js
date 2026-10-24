"use strict";
/* Brahma Foundry dashboard — vanilla SPA over the REST/WS surfaces. */

const $ = (s) => document.querySelector(s);
const $$ = (s) => [...document.querySelectorAll(s)];
const ORIGIN = location.origin;

function authHeaders(extra={}){ const h={...extra}; if(session.key) h["Authorization"]="Bearer "+session.key; return h; }
const api = (p, opts={}) => fetch(ORIGIN+p, opts).then(r=>r.json());

// --- tabs ---
$$(".tabs button").forEach(b => b.onclick = () => showTab(b.dataset.tab));
function showTab(name){
  $$(".tabs button").forEach(b=>b.classList.toggle("active", b.dataset.tab===name));
  $$(".panel").forEach(p=>p.classList.toggle("active", p.id===name));
  if(name==="catalog") loadCatalog();
  if(name==="marketplace") loadMarketplace();
  if(name==="account") renderAccount();
  if(name==="render") loadRenderModules();
}

// --- overview + telemetry ---
let organisms = [];
const colorMap = { Proteus:"#22d3ee", Relinquished:"#e94560", Golem:"#f59e0b", Typhon:"#a855f7", AgentSmith:"#22c55e" };
function colorFor(t){ return colorMap[t] || "#d4d4d8"; }

function connectWS(){
  let ws;
  try { ws = new WebSocket((location.protocol==="https:"?"wss://":"ws://")+location.host+"/ws"); }
  catch(e){ return; }
  ws.onmessage = (ev) => {
    const m = JSON.parse(ev.data);
    if(m.type==="telemetry"){
      organisms = m.organisms || [];
      $("#ov-engine").textContent = m.online ? "live" : "simulation";
      $("#ov-orgs").textContent = organisms.length;
      $("#ov-hint").innerHTML = m.online ? "" : "No SuperCollider engine detected — telemetry idle. Attach an engine (OSC 57122) to see live organisms.";
    }
  };
  ws.onclose = () => setTimeout(connectWS, 2000);
}

function drawTelemetry(){
  const c = $("#telemetry"); if(!c) return requestAnimationFrame(drawTelemetry);
  const ctx = c.getContext("2d");
  ctx.fillStyle = "rgba(13,7,22,0.35)"; ctx.fillRect(0,0,c.width,c.height);
  const t = performance.now()*0.001;
  if(organisms.length===0){
    ctx.fillStyle="#3a3346"; ctx.font="14px monospace";
    ctx.fillText("awaiting organism telemetry…", 20, c.height/2);
  }
  organisms.forEach((o,i)=>{
    const cx = (c.width/(organisms.length+1))*(i+1);
    const cy = c.height/2;
    const r = 30 + (o.coherence||0)*90;
    const jitter = (o.entropy||0);
    ctx.beginPath();
    for(let a=0;a<Math.PI*2;a+=0.1){
      const off = (Math.sin(a*5+t*2)*jitter);
      const x = cx+(r+off)*Math.cos(a), y = cy+(r+off)*Math.sin(a);
      a===0?ctx.moveTo(x,y):ctx.lineTo(x,y);
    }
    ctx.closePath();
    ctx.strokeStyle = colorFor(o.type); ctx.lineWidth=2; ctx.stroke();
    ctx.fillStyle = colorFor(o.type); ctx.font="11px monospace";
    ctx.fillText(o.type||o.id, cx-20, cy+r+20);
  });
  requestAnimationFrame(drawTelemetry);
}

async function refreshOverview(){
  const generation = session.generation;
  const key = session.key;
  const plans = (await api("/api/v1/plans")).data || [];
  if(session.generation !== generation) return;
  if(key){
    const u = await api("/api/v1/account/usage", { headers: { Authorization: "Bearer " + key } });
    if(session.generation !== generation) return;
    if(u.ok){
      $("#ov-plan").textContent = (plans.find(p=>p.id===u.data.plan)||{}).name || u.data.plan;
      $("#ov-usage").textContent = `${u.data.usage.count} / ${u.data.quota}`;
    }
  } else {
    $("#ov-plan").textContent = "—"; $("#ov-usage").textContent = "sign in";
  }
}

// --- render ---
async function loadRenderModules(){
  const sel = $("#rn-module"); if(sel.options.length) return;
  const mods = (await api("/api/v1/modules")).data || [];
  sel.innerHTML = mods.map(m=>`<option>${m.name}</option>`).join("");
}
$("#rn-go").onclick = async () => {
  if(!session.key){ $("#rn-out").textContent = "Sign in (Account tab) to get an API key first."; showTab("account"); return; }
  const body = { module: $("#rn-module").value, title: $("#rn-title").value, durationSec: Number($("#rn-dur").value) };
  $("#rn-out").textContent = "Rendering…";
  const res = await api("/api/v1/render", { method:"POST", headers: authHeaders({"content-type":"application/json"}), body: JSON.stringify(body) });
  $("#rn-out").textContent = JSON.stringify(res, null, 2);
  refreshOverview();
};

// --- catalog ---
async function loadCatalog(){
  const q = $("#cat-q").value.trim();
  const mods = (await api("/api/v1/modules"+(q?`?q=${encodeURIComponent(q)}`:""))).data || [];
  $("#cat-grid").innerHTML = mods.map(m=>`
    <div class="mod">
      <div class="cat">${m.category}${m.live?' · live':''}</div>
      <div class="name">${m.name}</div>
      <div class="desc">${m.description||""}</div>
      ${(m.tags||[]).map(t=>`<span class="tag">${t}</span>`).join("")}
    </div>`).join("");
}
$("#cat-q").oninput = () => { clearTimeout(window._catT); window._catT=setTimeout(loadCatalog,200); };

// --- marketplace ---
async function loadMarketplace(){
  const items = (await api("/api/v1/specimens")).data || [];
  if(!items.length){ $("#mk-grid").innerHTML = `<p class="hint">No specimens listed yet. Render one and list it for sale.</p>`; return; }
  $("#mk-grid").innerHTML = items.map(s=>`
    <div class="mod">
      <div class="cat">${s.sourceModule}</div>
      <div class="name">${s.title}</div>
      <div class="desc">by ${s.creator} ${s.simulated?'<span class="sim">· simulated</span>':''}</div>
      <div class="price">$${(s.priceCents/100).toFixed(2)}</div>
      <button onclick="buySpecimen('${s.id}')">Buy</button>
    </div>`).join("");
}
window.buySpecimen = async (id) => {
  const email = session.email || prompt("Email for purchase:");
  if(!email) return;
  const res = await api("/api/v1/billing/checkout/specimen", { method:"POST", headers:{"content-type":"application/json"}, body: JSON.stringify({ email, specimenId:id }) });
  if(res.ok && res.data.checkoutUrl) location.href = res.data.checkoutUrl;
  else alert(res.error||"Checkout failed");
};

// --- account ---
$("#ac-signup").onclick = () => doAuth("/api/v1/account/signup");
$("#ac-login").onclick = () => doAuth("/api/v1/account/login");
async function doAuth(path){
  const generation = session.generation;
  const email=$("#ac-email").value.trim(), password=$("#ac-pass").value;
  const res = await api(path, { method:"POST", headers:{"content-type":"application/json"}, body: JSON.stringify({email,password}) });
  if(session.generation !== generation) return;
  const msg = $("#ac-msg");
  if(!res.ok){ msg.style.color="#e94560"; msg.textContent=res.error; return; }
  if(path.endsWith("signup")){
    session.set(res.data.apiKey, email);
    msg.style.color="#d4a853"; msg.textContent="Account created. Your key is available for this page session only.";
  } else {
    // Never carry another account's key into this login.
    if(session.email !== email) session.clear();
    if(!session.key){ msg.style.color="#d4a853"; msg.textContent="Signed in. Enter your existing API key below to enable authenticated requests."; }
    session.set(session.key || "", email);
  }
  $("#ac-pass").value = "";
  if(path.endsWith("signup")){
    $("#ac-newkey-out").style.display="block";
    $("#ac-newkey-out").textContent="API key (shown once):\n"+res.data.apiKey;
  }
  renderAccount(); refreshOverview(); updateWho();
}
async function renderAccount(){
  const generation = session.generation;
  const key = session.key;
  const authed = !!session.email;
  $("#acct-auth").style.display = authed ? "none" : "block";
  $("#acct-body").style.display = authed ? "block" : "none";
  if(!authed) return;
  if(key){
    const headers = { Authorization: "Bearer " + key };
    const u = await api("/api/v1/account/usage", { headers });
    if(session.generation !== generation) return;
    if(u.ok){ $("#ac-plan").textContent=u.data.plan; $("#ac-usage").textContent=`${u.data.usage.count} / ${u.data.quota}`; }
    const keys = await api("/api/v1/account/keys", { headers });
    if(session.generation !== generation) return;
    if(keys.ok){
      $("#ac-keys").innerHTML = keys.data.map(k=>`<tr><td>${k.label}</td><td>${k.key}</td><td>${k.plan}</td><td>${k.status}</td></tr>`).join("");
    }
  }
}
$("#ac-use-key").onclick = async () => {
  const input = $("#ac-existing-key");
  const key = input.value.trim();
  const email = session.email;
  const generation = session.generation;
  input.value = "";
  if(!key) return;
  const result = await api("/api/v1/account/usage", { headers: { Authorization: "Bearer " + key } });
  if(session.generation !== generation || session.email !== email) return;
  if(!result.ok || result.data.ownerEmail !== email.toLowerCase()){
    $("#ac-key-msg").textContent="Enter an active API key for this account."; return;
  }
  session.set(key, email);
  $("#ac-key-msg").textContent="Key active for this page session.";
  renderAccount(); refreshOverview();
};
$("#ac-newkey").onclick = async () => {
  if(!session.key){ alert("Sign up first to obtain your first key."); return; }
  const generation = session.generation;
  const key = session.key;
  const res = await api("/api/v1/account/keys", { method:"POST", headers:{"content-type":"application/json", Authorization:"Bearer "+key}, body: JSON.stringify({label:"key"}) });
  if(session.generation !== generation) return;
  if(res.ok){
    const out=$("#ac-newkey-out"); out.style.display="block";
    out.textContent = "New API key (shown once):\n"+res.data.key;
    renderAccount();
  }
};

function updateWho(){
  const link=$("#auth-link");
  if(session.email){ link.textContent = session.email+" · sign out"; link.onclick=(e)=>{e.preventDefault();session.clear();$("#ac-msg").textContent="";$("#ac-key-msg").textContent="";$("#ac-plan").textContent="—";$("#ac-usage").textContent="—";$("#ac-newkey-out").textContent="";$("#ac-existing-key").value="";$("#ac-keys").textContent="";updateWho();renderAccount();refreshOverview();}; }
  else { link.textContent="Sign in"; link.onclick=(e)=>{e.preventDefault();showTab("account");}; }
}

// --- boot ---
if(location.search.includes("signup")) showTab("account");
if(location.search.includes("checkout=success")) refreshOverview();
connectWS();
drawTelemetry();
refreshOverview();
updateWho();
loadRenderModules();
