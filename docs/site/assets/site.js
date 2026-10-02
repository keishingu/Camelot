(() => {
  // Set this only after a public, tested release URL exists.
  const RELEASE = { available: false, version: "0.1.0", dmgUrl: "" };
  document.querySelectorAll("[data-version]").forEach((el) => { el.textContent = RELEASE.version; });
  if (RELEASE.available && RELEASE.dmgUrl) {
    document.querySelectorAll("[data-cta]").forEach((el) => {
      el.href = RELEASE.dmgUrl;
      el.removeAttribute("aria-disabled");
      el.classList.add("is-live");
      el.textContent = "Camelotをダウンロード";
    });
    document.querySelectorAll("[data-release-state]").forEach((el) => { el.textContent = "配布中"; });
    document.querySelectorAll("[data-release-heading]").forEach((el) => { el.textContent = "Camelotをダウンロード。"; });
    document.querySelectorAll("[data-release-note]").forEach((el) => { el.textContent = `バージョン${RELEASE.version} · macOS 26以降 · Universal`; });
  }

  const demo = document.querySelector("#demo");
  if (!demo) return;
  const status = demo.querySelector("[data-status]");
  const prefixView = demo.querySelector("[data-prefix]");
  const targets = [...demo.querySelectorAll("[data-hint]")];
  const hints = new Map();
  for (const target of targets) {
    const hint = document.createElement("span");
    hint.className = "demo-hint";
    hint.setAttribute("aria-hidden", "true");
    hint.textContent = target.dataset.hint;
    target.append(hint);
    hints.set(target, hint);
  }
  let prefix = "";
  let active = false;
  let resetTimer;
  let optionStartedAt = null;

  function reset(message = "Optionキーを押すと、操作できる項目にヒントが表示されます。") {
    clearTimeout(resetTimer);
    prefix = "";
    active = false;
    demo.dataset.state = "idle";
    prefixView.textContent = "—";
    targets.forEach((target) => target.classList.remove("is-fired"));
    hints.forEach((hint) => hint.classList.remove("is-hidden", "is-match"));
    status.textContent = message;
  }

  function showHints() {
    reset();
    active = true;
    demo.focus({ preventScroll: true });
    demo.dataset.state = "hints";
    status.textContent = "文字を入力して候補を選びます。例: S、続けてDでSave。";
  }

  function choose(target) {
    const input = target.querySelector("input[type=text]");
    const check = target.querySelector("input[type=checkbox]");
    const button = target.querySelector("button");
    targets.forEach((entry) => entry.classList.remove("is-fired"));
    target.classList.add("is-fired");
    active = false;
    demo.dataset.state = "fired";
    if (input) {
      input.focus();
      input.select();
      resetTimer = setTimeout(() => reset("入力欄にフォーカスしました。もう一度Optionを押すとデモを続けられます。"), 1300);
      status.textContent = "Display nameにフォーカスしました。";
      return;
    }
    if (check) check.checked = !check.checked;
    if (button) button.focus({ preventScroll: true });
    status.textContent = `${button?.textContent.trim() || "項目"}を選びました。`;
    resetTimer = setTimeout(() => reset(), 1300);
  }

  function enterKey(key) {
    if (key === "option") { showHints(); return; }
    if (key === "escape") { reset(); demo.focus({ preventScroll: true }); return; }
    if (key === "backspace") {
      if (!active || !prefix) return;
      prefix = prefix.slice(0, -1);
      updateMatches();
      return;
    }
    if (!active || !/^[a-z]$/i.test(key)) return;
    const next = prefix + key.toUpperCase();
    const matches = targets.filter((target) => target.dataset.hint.startsWith(next));
    if (!matches.length) return;
    prefix = next;
    const exact = matches.find((target) => target.dataset.hint === prefix);
    if (exact) { prefixView.textContent = prefix; choose(exact); return; }
    updateMatches();
  }

  function updateMatches() {
    demo.dataset.state = "filtered";
    prefixView.textContent = prefix;
    targets.forEach((target) => {
      const hint = hints.get(target);
      const match = target.dataset.hint.startsWith(prefix);
      hint.classList.toggle("is-hidden", !match);
      hint.classList.toggle("is-match", match);
    });
    status.textContent = `${prefix}で始まる候補を表示しています。`;
  }

  demo.addEventListener("keydown", (event) => {
    if (event.isComposing) { optionStartedAt = null; return; }
    if (event.key === "Alt") {
      if (!event.repeat && !event.shiftKey && !event.ctrlKey && !event.metaKey) {
        optionStartedAt = performance.now();
      }
      return;
    }
    optionStartedAt = null;
    if (event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return;
    if (event.key === "Escape") { event.preventDefault(); enterKey("escape"); }
    else if (event.key === "Backspace" && active) { event.preventDefault(); enterKey("backspace"); }
    else if (event.key.length === 1 && /^[a-z]$/i.test(event.key) && active) { event.preventDefault(); enterKey(event.key); }
  });
  demo.addEventListener("keyup", (event) => {
    if (event.key !== "Alt" || optionStartedAt === null) return;
    const elapsed = performance.now() - optionStartedAt;
    optionStartedAt = null;
    if (elapsed <= 300 && !event.shiftKey && !event.ctrlKey && !event.metaKey) {
      event.preventDefault();
      showHints();
    }
  });
  demo.addEventListener("pointerdown", (event) => {
    optionStartedAt = null;
    if (!event.target.closest("[data-demo-key]")) reset();
  });
  demo.addEventListener("focusout", (event) => {
    if (!demo.contains(event.relatedTarget)) {
      optionStartedAt = null;
      reset();
    }
  });
  demo.querySelectorAll("[data-demo-key]").forEach((button) => {
    button.addEventListener("click", () => enterKey(button.dataset.demoKey));
  });
})();
