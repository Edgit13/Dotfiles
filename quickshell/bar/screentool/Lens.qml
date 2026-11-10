import QtQuick

// Lens — crop a region, encode it and hand it to Google Lens in the browser.
// Ported from QuickSnip's LensMode. "sidebar" is best-effort and needs
// wlrctl + wtype plus a browser-side keybind; "newtab" is the default.
QtObject {
    id: root

    property color bgColor: "#111"
    property color fgColor: "#fff"

    function getCommand(image, cropJpg, lensHtml, x, y, w, h, openIn, browserClass) {
        const buildHtml = [
            `echo '<html><body style="margin:0;display:flex;justify-content:center;align-items:center;height:100vh;background:${root.bgColor};color:${root.fgColor};font-family:system-ui"><p>Searching with Google Lens…</p><form id="f" method="POST" enctype="multipart/form-data" action="https://lens.google.com/v3/upload"></form><script>'`,
            `echo "var b=atob('$B64');"`,
            `echo 'var a=new Uint8Array(b.length);for(var i=0;i<b.length;i++)a[i]=b.charCodeAt(i);var d=new DataTransfer();d.items.add(new File([a],"i.jpg",{type:"image/jpeg"}));var inp=document.createElement("input");inp.type="file";inp.name="encoded_image";inp.files=d.files;document.getElementById("f").appendChild(inp);document.getElementById("f").submit();'`,
            `echo '</script></body></html>'`
        ].join(" ; ")

        const crop = `magick "${image}" -crop ${w}x${h}+${x}+${y} -resize '1000x1000>' -strip -quality 85 "${cropJpg}"`
        const b64 = `B64=$(base64 -w0 "${cropJpg}" 2>/dev/null || base64 -b0 "${cropJpg}")`
        const html = `{ ${buildHtml} ; } > "${lensHtml}"`

        if (openIn === "sidebar") {
            const bc = browserClass || "firefox"
            const cmd = [
                crop, b64,
                `OLD_CLIP=$(wl-paste --no-newline --type text/plain 2>/dev/null || true)`,
                `printf '%s' "EDOTS_LENS:$B64" | wl-copy`,
                `sleep 0.05 && wlrctl window focus ${bc}`,
                `sleep 0.1 && wtype -M alt -k s -m alt`,
                `sleep 0.2 && if [ "$(wl-paste)" = "OPEN_SIDEBAR_PLEASE" ]; then wtype -M alt -k g -m alt; sleep 0.05; printf '%s' "EDOTS_LENS:$B64" | wl-copy; fi`,
                `sleep 2; printf '%s' "$OLD_CLIP" | wl-copy`,
                `(sleep 15 && rm -f "${cropJpg}") &`
            ].join(" ; ")
            return cmd
        }

        return `${crop} && ${b64} && ${html} && xdg-open "${lensHtml}" ; (sleep 15 && rm -f "${cropJpg}" "${lensHtml}") &`
    }
}
