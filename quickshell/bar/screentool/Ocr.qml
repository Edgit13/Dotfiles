import QtQuick

// Ocr — crop a region out of a screenshot and copy the recognised text.
// Ported from QuickSnip's OcrMode so the bar shell keeps a single capture UI.
QtObject {
    id: root

    // image: full-resolution screenshot, x/y/w/h: crop in image pixels.
    function getCommand(image, x, y, w, h, singleLine, rawMode, lang, notify) {
        const area = w * h
        const isSmall = area < 40000
        const isTiny = h < 30
        let upscale = ""
        if (isTiny)
            upscale = "-resize 400%"
        else if (isSmall)
            upscale = "-resize 200%"

        let psm = "6"
        if (isTiny || h < 50 || w / h > 10)
            psm = "7"

        let postProcess = ""
        if (rawMode)
            postProcess += " | sed 's/[[:space:]]*$//'"
        else
            postProcess += " | awk 'BEGIN{RS=\"\"; ORS=\"\\n\\n\"} {$1=$1; print}' | sed 's/[[:space:]]*$//'"
        if (singleLine)
            postProcess += " | tr '\\n' ' ' | sed 's/  */ /g; s/[[:space:]]*$//'"

        const finalPipe = postProcess + " | wl-copy"
        const tmp = "/dev/shm/edots-ocr-" + Date.now()

        let cmd = `
            magick "${image}" -crop ${w}x${h}+${x}+${y} ${upscale} -colorspace Gray -depth 8 "${tmp}.pnm"
            if [ "$(magick "${tmp}.pnm" -format "%[fx:mean<0.5?1:0]" info:)" = "0" ]; then
                magick "${tmp}.pnm" -negate "${tmp}.pnm"
            fi
            TEXT=$(tesseract "${tmp}.pnm" - -l ${lang} --psm ${psm} --oem 1 2>/dev/null)
            if [ \$(printf '%s' "\$TEXT" | tr -d '[:space:]' | wc -c) -lt 3 ]; then
                magick "${tmp}.pnm" -negate "${tmp}.pnm"
                TEXT2=$(tesseract "${tmp}.pnm" - -l ${lang} --psm ${psm} --oem 1 2>/dev/null)
                if [ \$(printf '%s' "\$TEXT2" | tr -d '[:space:]' | wc -c) -gt \$(printf '%s' "\$TEXT" | tr -d '[:space:]' | wc -c) ]; then
                    TEXT="\$TEXT2"
                fi
            fi
            printf '%s' "$TEXT" ${finalPipe}
            rm -f "${tmp}.pnm"
        `
        if (notify) {
            cmd += `
            CLEAN_TEXT=\$(printf '%s' "\$TEXT" | tr '\\n' ' ' | sed 's/  */ /g')
            TEXT_BODY=\$(printf '%s' "\$CLEAN_TEXT" | head -c 100)
            [ \${#CLEAN_TEXT} -gt 100 ] && TEXT_BODY="\${TEXT_BODY}..."
            if [ -n "\$CLEAN_TEXT" ]; then
                notify-send -a "OCR" "Copied" "\$TEXT_BODY" -t 3000
            else
                notify-send -a "OCR" -u low "OCR" "No text found" -t 2500
            fi
            `
        }
        return cmd
    }
}
