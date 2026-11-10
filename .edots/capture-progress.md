# Capture — progress

## Статус: завершено (перенесено в bar shell)

QuickSnip більше не існує як окремий shell. Усе захоплення живе в
`quickshell/bar/screentool/`:

- `ScreenTool.qml` — оверлей виділення, скріншот (region / monitor), запис, OCR/Lens.
- `Ocr.qml` — порт `OcrMode.qml` (tesseract + magick, upscale, polarity check, wl-copy).
- `Lens.qml` — порт `LensMode.qml` (crop → base64 → локальна HTML-сторінка → браузер).

## Що вміє

- Region → Screenshot (clipboard / файл), Monitor → Screenshot.
- Region → OCR (`O`), Region → Lens (`L`), Region / Monitor → Record (`R`).
- Налаштування: Settings → Capture & recording (`capture.json`).
- IPC: `screentool open|close|toggle|ocr|lens|stop`.
- CLI: `edots screenshot [stop]`, `edots ocr`, `edots lens`.

## Нотатки

- Кольори беруться з `~/.config/quickshell/colors.json` через тему бару.
- Запис екрана — `RecordService` + `wf-recorder`, індикатор у барі.
- Старі файли QuickSnip видалено; історію можна знайти в git (коміт `c3b5445`).
