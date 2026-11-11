/* Edots docs — small motion layer.
   Progressive enhancement: nothing is hidden or broken without JavaScript.
   Honours prefers-reduced-motion. */

(() => {
    "use strict";

    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const fine = window.matchMedia("(hover: hover) and (pointer: fine)").matches;

    /* ── scroll progress ─────────────────────────────────────── */
    const bar = document.createElement("div");
    bar.className = "scroll-progress";
    document.body.prepend(bar);

    let ticking = false;
    const onScroll = () => {
        if (ticking) return;
        ticking = true;
        requestAnimationFrame(() => {
            const max = document.documentElement.scrollHeight - window.innerHeight;
            const p = max > 0 ? Math.min(window.scrollY / max, 1) : 0;
            bar.style.transform = `scaleX(${p})`;
            document.querySelector(".topbar")?.classList.toggle("scrolled", window.scrollY > 8);
            ticking = false;
        });
    };
    window.addEventListener("scroll", onScroll, { passive: true });
    onScroll();

    /* ── reveal on scroll ───────────────────────────────────── */
    if (!reduce && "IntersectionObserver" in window) {
        const observer = new IntersectionObserver((entries) => {
            for (const entry of entries) {
                if (!entry.isIntersecting) continue;
                entry.target.classList.add("in");
                observer.unobserve(entry.target);
            }
        }, { rootMargin: "0px 0px -8% 0px", threshold: 0.05 });

        const selector = [
            ".wrap > h2",
            ".wrap > .sub",
            ".wrap > figure",
            ".wrap > table",
            ".wrap > .compare",
            ".wrap > .pill-row",
            ".wrap > .note",
            ".wrap > .grid > *",
            ".wrap > .split > *",
            ".wrap > .prose > *"
        ].join(",");

        for (const section of document.querySelectorAll("section")) {
            const items = section.querySelectorAll(selector);
            items.forEach((el, i) => {
                el.classList.add("reveal");
                el.style.setProperty("--d", `${Math.min(i, 8) * 55}ms`);
                observer.observe(el);
            });
        }
    }

    /* ── pointer spotlight in the hero ──────────────────────── */
    if (!reduce && fine) {
        const hero = document.querySelector(".hero");
        if (hero) {
            hero.addEventListener("pointermove", (event) => {
                const rect = hero.getBoundingClientRect();
                hero.style.setProperty("--mx", `${event.clientX - rect.left}px`);
                hero.style.setProperty("--my", `${event.clientY - rect.top}px`);
            }, { passive: true });
        }
    }

    /* ── copy buttons on code blocks ────────────────────────── */
    const label = (btn, text) => { btn.textContent = text; };
    for (const pre of document.querySelectorAll("pre")) {
        const btn = document.createElement("button");
        btn.type = "button";
        btn.className = "copy";
        label(btn, "copy");
        btn.setAttribute("aria-label", "Copy code");
        btn.addEventListener("click", async () => {
            const code = pre.querySelector("code");
            const text = (code ?? pre).innerText.trim();
            try {
                await navigator.clipboard.writeText(text);
                btn.classList.add("ok");
                label(btn, "copied");
            } catch {
                label(btn, "select it");
            }
            window.setTimeout(() => {
                btn.classList.remove("ok");
                label(btn, "copy");
            }, 1600);
        });
        pre.appendChild(btn);
    }

    /* ── pause the ticker when it is off screen ─────────────── */
    const ticker = document.querySelector(".ticker-track");
    if (ticker && "IntersectionObserver" in window) {
        new IntersectionObserver(([entry]) => {
            ticker.style.animationPlayState = entry.isIntersecting ? "running" : "paused";
        }).observe(ticker);
    }
})();
