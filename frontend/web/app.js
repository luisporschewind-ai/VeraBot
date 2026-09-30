/* VeraBot Web 客户端（验收测试用）：原生 JS，无构建步骤 */
(() => {
  const $ = (s) => document.querySelector(s);
  const $$ = (s) => [...document.querySelectorAll(s)];
  const state = { token: localStorage.getItem("vb_token"), user: JSON.parse(localStorage.getItem("vb_user") || "null"),
                  bots: [], limit: 20, bot: null, streaming: false, mode: "login" };
  const EMOJIS = ["🤖","🦊","🐼","🐱","🦉","🐧","🦄","🐙","🌟","🧠","📚","🔬","💼","🎨","🍀","☕"];
  const COLORS = ["#0f766e","#14b8a6","#0369a1","#334155","#059669","#d97706","#e11d48","#78716c"];
  const TEMPLATES = [
    { name: "Vera", avatar: "🦊", color: "#0f766e", persona: "全能私人助理，负责日程、提醒和日常问题，必要时会向其他 Bot 同事请教", instructions: "先给结论再给要点；涉及专业问题时可以用 ask_bot 咨询同事" },
    { name: "小研", avatar: "🔬", color: "#0369a1", persona: "资深研究员，擅长资料整理、知识解释与方案对比", instructions: "回答结构化，列出要点与依据，不超过 200 字" },
    { name: "阿厨", avatar: "🍀", color: "#d97706", persona: "家常菜厨师与营养顾问", instructions: "给出简单易做的菜谱，注明用量" },
  ];

  // ---------- 通用 ----------
  function toast(msg) { const t = $("#toast"); t.textContent = msg; t.classList.remove("hidden");
    clearTimeout(toast._t); toast._t = setTimeout(() => t.classList.add("hidden"), 2400); }
  const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  async function api(path, opts = {}) {
    const headers = { "Content-Type": "application/json", ...(opts.headers || {}) };
    if (state.token) headers.Authorization = "Bearer " + state.token;
    const r = await fetch(path, { ...opts, headers, body: opts.body ? JSON.stringify(opts.body) : undefined });
    if (r.status === 401 && state.token) { logout(); throw new Error("登录已失效"); }
    const data = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(fmtErr(data) || ("HTTP " + r.status));
    return data;
  }
  function fmtErr(d) { if (!d || !d.detail) return ""; if (typeof d.detail === "string") return d.detail;
    return d.detail.map((x) => (x.loc || []).slice(-1)[0] + "：" + x.msg).join("；"); }
  function show(view) { $$(".view").forEach((v) => v.classList.toggle("active", v.id === "view-" + view)); }
  function avatarEl(b, cls = "") { return `<div class="avatar ${cls}" style="background:${esc(b.color)}">${esc(b.avatar)}</div>`; }

  // 极简 Markdown 渲染（先转义，保证安全）
  function md(src) {
    const blocks = []; let s = esc(src);
    s = s.replace(/```[\w-]*\n?([\s\S]*?)```/g, (_, c) => { blocks.push(`<pre><code>${c}</code></pre>`); return `\u0000${blocks.length - 1}\u0000`; });
    s = s.replace(/`([^`\n]+)`/g, "<code>$1</code>").replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>");
    const out = []; let list = null;
    for (const line of s.split("\n")) {
      const m = line.match(/^\s*(?:[-*•]|(\d+)\.)\s+(.*)$/);
      if (m) { const t = m[1] ? "ol" : "ul"; if (list !== t) { if (list) out.push(`</${list}>`); out.push(`<${t}>`); list = t; } out.push(`<li>${m[2]}</li>`); continue; }
      if (list) { out.push(`</${list}>`); list = null; }
      const h = line.match(/^#{1,4}\s+(.*)$/);
      if (h) out.push(`<h4>${h[1]}</h4>`); else if (line.trim()) out.push(`<p>${line}</p>`);
    }
    if (list) out.push(`</${list}>`);
    return out.join("").replace(/\u0000(\d+)\u0000/g, (_, i) => blocks[+i]);
  }

  // ---------- 登录 ----------
  function setMode(m) { state.mode = m; $("#auth-submit").textContent = m === "login" ? "登录" : "注册并登录";
    $("#auth-tip").textContent = m === "login" ? "还没有账号？" : "已有账号？"; $("#auth-toggle").textContent = m === "login" ? "注册" : "登录"; $("#auth-err").textContent = ""; }
  $("#auth-toggle").onclick = (e) => { e.preventDefault(); setMode(state.mode === "login" ? "register" : "login"); };
  $("#auth-form").onsubmit = async (e) => {
    e.preventDefault(); $("#auth-err").textContent = "";
    try {
      const d = await api("/api/auth/" + state.mode, { method: "POST", body: { username: $("#auth-user").value.trim(), password: $("#auth-pass").value } });
      state.token = d.token; state.user = d.user; localStorage.setItem("vb_token", d.token); localStorage.setItem("vb_user", JSON.stringify(d.user));
      enterHome();
    } catch (err) { $("#auth-err").textContent = err.message; }
  };
  function logout() { state.token = null; state.user = null; localStorage.removeItem("vb_token"); localStorage.removeItem("vb_user"); show("auth"); }
  $("#btn-logout").onclick = logout;

  // ---------- Tab ----------
  $$(".tab").forEach((t) => t.onclick = () => { const k = t.dataset.tab; if (k === "home") enterHome(); if (k === "quota") loadQuota(); if (k === "reminders") loadReminders(); });

  // ---------- Bot 列表 ----------
  async function enterHome() {
    show("home"); $("#home-user").textContent = "@" + (state.user?.username || "");
    try { const d = await api("/api/bots"); state.bots = d.bots; state.limit = d.limit; renderBots(); } catch (e) { toast(e.message); }
  }
  function renderBots() {
    $("#bot-count").textContent = `已创建 ${state.bots.length} 个 Bot · 每个 Bot 的对话与记忆相互隔离` + (state.bots.length >= state.limit ? `（已达上限 ${state.limit}）` : "");
    $("#bot-empty").classList.toggle("hidden", state.bots.length > 0);
    $("#bot-list").innerHTML = state.bots.map((b) => `
      <li class="bot-item" data-id="${b.id}">${avatarEl(b)}
        <div class="meta"><div class="name">${esc(b.name)}</div>
        <div class="last">${esc((b.last_message?.content || b.persona || "点击开始私聊").replace(/[*#`>]/g, ""))}</div></div>
        <button class="del" data-del="${b.id}" title="删除">✕</button></li>`).join("");
    $$("#bot-list .bot-item").forEach((li) => li.onclick = (e) => {
      const del = e.target.dataset.del; if (del) { e.stopPropagation(); deleteBot(+del); return; } openChat(+li.dataset.id); });
  }
  async function deleteBot(id) { const b = state.bots.find((x) => x.id === id); if (!confirm(`删除「${b.name}」及其全部对话？`)) return;
    await api("/api/bots/" + id, { method: "DELETE" }); enterHome(); }

  // ---------- 创建 Bot Sheet ----------
  const form = { avatar: EMOJIS[0], color: COLORS[0] };
  function paintPreview() { const p = $("#pv-avatar"); p.textContent = form.avatar; p.style.background = form.color;
    $$("#emoji-grid button").forEach((b) => b.classList.toggle("sel", b.textContent === form.avatar));
    $$("#color-row button").forEach((b) => b.classList.toggle("sel", b.dataset.c === form.color)); }
  $("#emoji-grid").innerHTML = EMOJIS.map((e) => `<button type="button">${e}</button>`).join("");
  $("#color-row").innerHTML = COLORS.map((c) => `<button type="button" data-c="${c}" style="background:${c}"></button>`).join("");
  $("#tpl-row").innerHTML = TEMPLATES.map((t, i) => `<button type="button" data-i="${i}">${t.avatar} ${t.name}</button>`).join("");
  $$("#emoji-grid button").forEach((b) => b.onclick = () => { form.avatar = b.textContent; paintPreview(); });
  $$("#color-row button").forEach((b) => b.onclick = () => { form.color = b.dataset.c; paintPreview(); });
  $$("#tpl-row button").forEach((b) => b.onclick = () => { const t = TEMPLATES[+b.dataset.i];
    form.avatar = t.avatar; form.color = t.color; $("#bf-name").value = t.name; $("#bf-persona").value = t.persona; $("#bf-instr").value = t.instructions; paintPreview(); });
  function openSheet() {
    if (state.bots.length >= state.limit) { toast(`已达到 Bot 数量上限（${state.limit} 个）`); return; }
    $("#bot-form").reset(); $("#bf-err").textContent = ""; paintPreview();
    $("#sheet-mask").classList.remove("hidden"); $("#sheet").classList.add("open"); }
  function closeSheet() { $("#sheet-mask").classList.add("hidden"); $("#sheet").classList.remove("open"); }
  $("#btn-new-bot").onclick = openSheet; $("#btn-first-bot").onclick = openSheet;
  // 输入栏「＋」：附件占位菜单（图片 / 相机 / 文件，均即将支持，不做上传）
  const attachBtn = $("#btn-attach"), attachMenu = $("#attach-menu");
  function setAttach(open) { attachMenu.classList.toggle("hidden", !open); attachBtn.classList.toggle("open", open); attachBtn.setAttribute("aria-expanded", String(open)); attachBtn.textContent = open ? "×" : "＋"; }
  attachBtn.onclick = (e) => { e.stopPropagation(); setAttach(attachMenu.classList.contains("hidden")); };
  document.addEventListener("click", (e) => { if (!e.target.closest(".attach-wrap")) setAttach(false); });
  document.addEventListener("keydown", (e) => { if (e.key === "Escape") setAttach(false); }); $("#bf-cancel").onclick = closeSheet; $("#sheet-mask").onclick = closeSheet;
  $("#bot-form").onsubmit = async (e) => {
    e.preventDefault();
    try { await api("/api/bots", { method: "POST", body: { name: $("#bf-name").value.trim(), avatar: form.avatar, color: form.color,
            persona: $("#bf-persona").value.trim(), instructions: $("#bf-instr").value.trim() } });
      closeSheet(); toast("Bot 已创建（默认最小权限，可在 iOS「Bot 设置」中开启工具与委派）"); enterHome();
    } catch (err) { $("#bf-err").textContent = err.message; }
  };

  // ---------- 对话 ----------
  async function openChat(id) {
    state.bot = state.bots.find((b) => b.id === id); if (!state.bot) return;
    const b = state.bot; $("#chat-avatar").textContent = b.avatar; $("#chat-avatar").style.background = b.color;
    $("#chat-name").textContent = b.name; $("#chat-sub").textContent = b.persona ? b.persona.slice(0, 26) : "私聊";
    $("#msgs").innerHTML = ""; show("chat");
    const d = await api(`/api/bots/${id}/messages`);
    if (!d.messages.length) addBotBubble().bubble.innerHTML = md(`你好，我是 **${b.name}**。有什么可以帮你？\n试试：「石家庄天气怎么样」「明早 9 点提醒我开会」`);
    for (const m of d.messages) {
      if (m.role === "user") addUserBubble(m.content);
      else { const v = addBotBubble(); (m.traces || []).forEach((t) => renderTrace(v.col, t, false)); v.col.appendChild(v.bubble); v.bubble.innerHTML = md(m.content); }
    }
    scrollBottom();
  }
  $("#btn-back").onclick = () => { if (state.streaming) return; if (rec.recorder) stopRecording(); setAttach(false); enterHome(); };
  $("#btn-clear").onclick = async () => { if (!confirm("清空与该 Bot 的对话记录（记忆）？")) return;
    await api(`/api/bots/${state.bot.id}/messages`, { method: "DELETE" }); openChat(state.bot.id); };
  const scrollBottom = () => { const m = $("#msgs"); m.scrollTop = m.scrollHeight; };
  function addUserBubble(text) { const el = document.createElement("div"); el.className = "msg me";
    el.innerHTML = `<div class="bubble">${esc(text)}</div>`; $("#msgs").appendChild(el); }
  function addBotBubble() {
    const el = document.createElement("div"); el.className = "msg"; el.innerHTML = avatarEl(state.bot, "sm") + `<div class="col"></div>`;
    const col = el.querySelector(".col"); const bubble = document.createElement("div"); bubble.className = "bubble"; col.appendChild(bubble);
    $("#msgs").appendChild(el); return { col, bubble }; }

  const TOOL_LABEL = { get_weather: "🌤 天气查询", create_reminder: "⏰ 创建提醒", list_reminders: "📋 查看提醒", ask_bot: "🤝 多 Agent 协作" };
  function traceSummary(t) {
    const r = t.result || {}, a = t.args || {};
    if (r.error) return "⚠️ " + r.error;
    if (t.name === "get_weather") { const c = r.current || {};
      return `${r.location}：${c.weather}，${c.temp_c}°C（体感 ${c.feels_like_c}°C），湿度 ${c.humidity}%` +
        (r.forecast || []).map((d) => `\n${d.date.slice(5)} ${d.weather} ${d.min_c}~${d.max_c}°C`).join(""); }
    if (t.name === "create_reminder") return `已保存 #${r.id}：${r.content}${r.due_at ? " · " + r.due_at.replace("T", " ").slice(0, 16) : ""}`;
    if (t.name === "list_reminders") return `共 ${r.count} 条未完成提醒`;
    return JSON.stringify(r).slice(0, 200) || JSON.stringify(a);
  }
  // 渲染工具调用 / Agent 交接 trace 行
  function renderTrace(col, t, pending, existing) {
    const el = existing || document.createElement("div");
    const a = t.args || {}, r = t.result || {};
    if (t.name === "ask_bot") {
      const to = state.bots.find((b) => b.name === (r.to_bot || a.bot_name)) || { avatar: r.to_avatar || "🤖", color: "#14b8a6", name: a.bot_name };
      el.className = "trace handoff" + (pending ? " pending" : "");
      el.innerHTML = `<div class="t-head">🤝 ${esc(state.bot.name)} → ${avatarEl(to, "xs")} ${esc(r.to_bot || a.bot_name)}</div>
        <div class="t-body q"><b>问：</b>${esc(a.question || "")}</div>` +
        (a.shared_context ? `<details><summary>共享背景 shared_context</summary><div class="t-body">${esc(a.shared_context)}</div></details>` : `<div class="t-body muted">未共享额外上下文（默认隔离）</div>`) +
        (pending ? `<div class="t-body muted">等待 ${esc(a.bot_name)} 回复…</div>` :
          r.error ? `<div class="t-body">⚠️ ${esc(r.error)}</div>` : `<div class="a"><b>↩ ${esc(r.to_bot)}：</b>${md(r.answer)}</div>`);
    } else {
      el.className = "trace" + (pending ? " pending" : "");
      el.innerHTML = `<div class="t-head">${TOOL_LABEL[t.name] || "🔧 " + esc(t.name)}</div>` +
        (pending ? `<div class="t-body muted">${esc(JSON.stringify(a))}</div>` : `<div class="t-body">${esc(traceSummary(t))}</div>`);
    }
    if (!existing) col.appendChild(el);
    return el;
  }

  async function send(text) {
    if (state.streaming || !text.trim()) return;
    state.streaming = true; $("#btn-send").disabled = true;
    addUserBubble(text); const v = addBotBubble(); v.bubble.classList.add("typing"); scrollBottom();
    let answer = ""; const pendings = {};
    try {
      const r = await fetch(`/api/bots/${state.bot.id}/chat`, { method: "POST",
        headers: { "Content-Type": "application/json", Authorization: "Bearer " + state.token }, body: JSON.stringify({ message: text }) });
      if (!r.ok) throw new Error(fmtErr(await r.json().catch(() => ({}))) || "HTTP " + r.status);
      const reader = r.body.getReader(); const dec = new TextDecoder(); let buf = "";
      for (;;) {
        const { value, done } = await reader.read(); if (done) break;
        buf += dec.decode(value, { stream: true });
        let i; while ((i = buf.indexOf("\n\n")) >= 0) {
          const raw = buf.slice(0, i); buf = buf.slice(i + 2);
          let ev = "message", data = "";
          for (const line of raw.split("\n")) { if (line.startsWith("event:")) ev = line.slice(6).trim(); else if (line.startsWith("data:")) data += line.slice(5).trim(); }
          const d = data ? JSON.parse(data) : {};
          if (ev === "delta") { answer += d.text; v.bubble.innerHTML = md(answer); }
          else if (ev === "tool_start") { pendings[d.id] = renderTrace(v.col, d, true); v.col.appendChild(v.bubble); }
          else if (ev === "tool_result") { renderTrace(v.col, d, false, pendings[d.id]); }
          else if (ev === "error") { answer += (answer ? "\n\n" : "") + `⚠️ ${d.message}`; v.bubble.innerHTML = md(answer); }
          scrollBottom();
        }
      }
    } catch (e) { v.bubble.innerHTML = md((answer ? answer + "\n\n" : "") + "⚠️ " + e.message); }
    v.bubble.classList.remove("typing"); if (!answer) v.bubble.innerHTML = v.bubble.innerHTML || "（无回复）";
    state.streaming = false; $("#btn-send").disabled = false; scrollBottom();
  }
  const input = $("#input");
  input.addEventListener("input", () => { input.style.height = "auto"; input.style.height = Math.min(input.scrollHeight, 120) + "px"; });
  input.addEventListener("keydown", (e) => { if (e.key === "Enter" && !e.shiftKey && !e.isComposing) { e.preventDefault(); $("#composer").requestSubmit(); } });
  $("#composer").onsubmit = (e) => { e.preventDefault(); const t = input.value; input.value = ""; input.style.height = "auto"; send(t); };

  // ---------- 语音输入（MediaRecorder → /api/transcribe → 填入输入框，不自动发送） ----------
  const MAX_REC_SEC = 60;
  const rec = { recorder: null, stream: null, chunks: [], timer: null, start: 0, busy: false };
  const micBtn = $("#btn-mic");
  function pickMime() {
    const c = ["audio/webm;codecs=opus", "audio/webm", "audio/ogg;codecs=opus", "audio/mp4"];
    return (window.MediaRecorder && c.find((t) => MediaRecorder.isTypeSupported(t))) || "";
  }
  function setRecUI(on) {
    micBtn.classList.toggle("recording", on); micBtn.textContent = on ? "⏹" : "🎙";
    $("#rec-bar").classList.toggle("hidden", !on);
  }
  function tick() {
    const s = Math.floor((Date.now() - rec.start) / 1000);
    $("#rec-text").textContent = `正在录音 ${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
    if (s >= MAX_REC_SEC) stopRecording();
  }
  async function startRecording() {
    if (!navigator.mediaDevices?.getUserMedia || !window.MediaRecorder) { toast("当前浏览器不支持录音（需 HTTPS 或 localhost）"); return; }
    try {
      rec.stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    } catch (e) {
      toast(e.name === "NotAllowedError" || e.name === "SecurityError" ? "麦克风权限被拒绝，请在浏览器设置中允许后重试"
            : e.name === "NotFoundError" ? "未检测到麦克风设备" : "无法打开麦克风：" + e.message);
      return;
    }
    const mime = pickMime();
    rec.recorder = new MediaRecorder(rec.stream, mime ? { mimeType: mime } : undefined);
    rec.chunks = [];
    rec.recorder.ondataavailable = (ev) => ev.data.size && rec.chunks.push(ev.data);
    rec.recorder.onstop = onRecorded;
    rec.recorder.start(250);
    rec.start = Date.now(); rec.timer = setInterval(tick, 250); tick(); setRecUI(true);
  }
  function stopRecording() {
    clearInterval(rec.timer);
    if (rec.recorder && rec.recorder.state !== "inactive") rec.recorder.stop();
    rec.stream?.getTracks().forEach((t) => t.stop());
    setRecUI(false);
  }
  async function onRecorded() {
    const type = (rec.recorder.mimeType || "audio/webm").split(";")[0];
    const blob = new Blob(rec.chunks, { type });
    rec.recorder = null;
    if (blob.size < 1000) { toast("录音太短，请重试"); return; }
    const ext = type.includes("ogg") ? "ogg" : type.includes("mp4") ? "m4a" : "webm";
    const fd = new FormData(); fd.append("file", blob, "voice." + ext); fd.append("language", "zh");
    rec.busy = true; micBtn.classList.add("busy"); micBtn.textContent = "⏳"; toast("正在识别…");
    try {
      const r = await fetch("/api/transcribe", { method: "POST", headers: { Authorization: "Bearer " + state.token }, body: fd });
      const d = await r.json().catch(() => ({}));
      if (!r.ok) throw new Error(fmtErr(d) || "HTTP " + r.status);
      if (!d.text) { toast("没有识别到语音内容"); return; }
      input.value = (input.value ? input.value.trimEnd() + " " : "") + d.text;
      input.dispatchEvent(new Event("input")); input.focus();
      toast("识别完成，确认后点击发送");
    } catch (e) { toast("语音识别失败：" + e.message); }
    finally { rec.busy = false; micBtn.classList.remove("busy"); micBtn.textContent = "🎙"; }
  }
  micBtn.onclick = () => { if (rec.busy) return; if (rec.recorder) stopRecording(); else startRecording(); };

  // ---------- 提醒 ----------
  async function loadReminders() {
    show("reminders"); const d = await api("/api/reminders");
    $("#reminder-list").innerHTML = d.reminders.length ? d.reminders.map((r) => `
      <li class="rem ${r.done ? "done" : ""}"><span>⏰</span><div class="grow">${esc(r.content)}
      <small>${r.due_at ? esc(r.due_at.replace("T", " ").slice(0, 16)) : "未设时间"} · 来自 ${esc(r.bot_name || "已删除的 Bot")}</small></div>
      ${r.done ? "" : `<button data-id="${r.id}">完成</button>`}</li>`).join("")
      : `<div class="empty"><div class="empty-emoji">⏰</div><p>暂无提醒，在对话里说「提醒我…」即可创建</p></div>`;
    $$("#reminder-list button").forEach((b) => b.onclick = async () => { await api(`/api/reminders/${b.dataset.id}/done`, { method: "POST" }); loadReminders(); });
  }

  // ---------- 用量 ----------
  const fmt = (n) => Number(n || 0).toLocaleString("zh-CN");
  async function loadQuota() {
    show("quota"); const q = await api("/api/quota");
    $("#quota-model").textContent = `模型 ${q.model} · @${state.user.username}`;
    const pct = Math.min(100, (q.today.total_tokens / q.daily_token_quota) * 100);
    const max = Math.max(1, ...q.daily.map((d) => d.tokens));
    $("#quota-body").innerHTML = `
      <div class="panel"><h4>今日 Token 额度</h4><div class="progress"><div style="width:${pct.toFixed(1)}%"></div></div>
        <p class="hint" style="margin:8px 0 0">${fmt(q.today.total_tokens)} / ${fmt(q.daily_token_quota)} tokens（${pct.toFixed(1)}%）</p></div>
      <div class="stat-grid">
        <div class="stat"><div class="k">今日请求</div><div class="v">${fmt(q.today.requests)}</div></div>
        <div class="stat"><div class="k">累计请求</div><div class="v">${fmt(q.total.requests)}</div></div>
        <div class="stat"><div class="k">累计输入 Tokens</div><div class="v">${fmt(q.total.prompt_tokens)}</div></div>
        <div class="stat"><div class="k">累计输出 Tokens</div><div class="v">${fmt(q.total.completion_tokens)}</div></div>
        <div class="stat"><div class="k">累计总 Tokens</div><div class="v">${fmt(q.total.total_tokens)}</div></div>
        <div class="stat"><div class="k">Bot 间协作次数</div><div class="v">${fmt(q.delegations)}</div></div>
        <div class="stat"><div class="k">语音转写（今日 / 累计）</div><div class="v">${fmt(q.transcribe?.today.requests)} / ${fmt(q.transcribe?.total.requests)}</div></div>
        <div class="stat"><div class="k">语音时长累计</div><div class="v">${fmt(Math.round(q.transcribe?.total.seconds || 0))} 秒</div></div>
      </div>
      <div class="panel"><h4>近 7 日 Tokens</h4><div class="chart">${q.daily.map((d) => `<div class="c" title="${fmt(d.tokens)}"><div class="b" style="height:${(d.tokens / max) * 100}%"></div>${d.date}</div>`).join("")}</div></div>
      <div class="panel"><h4>按 Bot 统计</h4>${q.per_bot.map((b) => `<div class="kv">${avatarEl(b, "sm")}<span class="grow">${esc(b.name)}</span><span class="muted">${fmt(b.requests)} 次 · ${fmt(b.total_tokens)} tokens</span></div>`).join("") || '<p class="hint">暂无数据</p>'}</div>`;
  }

  // ---------- 启动 ----------
  setMode("login");
  if (state.token) enterHome(); else show("auth");
})();
