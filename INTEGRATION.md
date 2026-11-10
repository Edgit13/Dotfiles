# Захоплення екрана (screentool)

Захоплення живе в барі Quickshell — окремого процесу QuickSnip більше немає.

## Де що лежить

    quickshell/bar/screentool/ScreenTool.qml   ← оверлей виділення, скріншот, запис
    quickshell/bar/screentool/Ocr.qml          ← OCR-команда (tesseract + magick)
    quickshell/bar/screentool/Lens.qml         ← Google Lens через локальну HTML-сторінку
    quickshell/bar/services/RecordService.qml  ← запис екрана (wf-recorder)
    quickshell/bar/settings/Schema.qml         ← Settings → Capture & recording

## Використання

    edots screenshot            # оверлей: виділити → Enter
    edots screenshot stop       # зупинити запис
    edots ocr                   # виділити регіон → текст у буфер
    edots lens                  # виділити регіон → Google Lens у браузері

Гарячі клавіші в оверлеї: `O` — OCR, `L` — Lens, `R` — запис,
`Enter` — зберегти/скопіювати, `Esc` — скасувати.

Бінди: `SUPER+U` / `Print` → `edots screenshot`, `SUPER+SHIFT+U` →
`mango/scripts/lens.sh` (викликає `edots lens`).

## Налаштування

`~/.config/quickshell/capture.json` (Settings → Capture & recording):

- `ocrLang` — eng / ukr / rus (потрібні відповідні `tesseract-data-*`)
- `ocrSingleLine`, `ocrRaw`, `ocrNotify`
- `lensOpen` — `newtab` (типово) або `sidebar` (потребує wlrctl + wtype)
- `screenshotDir` — тека скріншотів

## Залежності

`grim`, `slurp`, `imagemagick` (`magick`), `wl-clipboard`, `tesseract`
(+ мовні дані), `wf-recorder`, `libnotify`, `xdg-utils`.

Кольори оверлея беруться з `~/.config/quickshell/colors.json` через тему бару,
тож зміна шпалер автоматично перефарбовує і screentool.
