# Выгрузка и обратный импорт текстов (H59)

## Выгрузить
```
python3 -I tools/export_texts.py                 # → Docs/text_export/ru_all.tsv
python3 -I tools/export_texts.py --out /tmp/ru_all.tsv --stats
```
Один TSV в UTF-8, колонки: `id`, `speaker`, `scene_room`, `context`, `text`.
- `id` — адрес текста в данных: `text:<ключ>` (text/*.json), `text:<ключ>#line` (та же запись репликой
  персонажа), `scene:<id>/lines[N].text|voice_text|options[<id>].text|then[K].text`, `scene:<id>/goal`,
  `scene:<id>/hints[K]`, `quest:<id>/…`, `item:<id>/name`, `char:<id>/name`, `loc:<id>/name`, `flag:<id>/desc`,
  `ui_code:<файл>:<хеш>` (строка зашита в коде — импорт её не пишет).
- `speaker` — кто говорит: id персонажа, `agata` (мысли Агаты), `narrator` (закадровый голос), `ui`
  (интерфейс, подписи, кнопки, журнал), `written` (текст на листе или доске крупного плана).
- `context` — где и когда звучит текст.
- Табуляция, перевод строки и `\` записаны как `\t`, `\n`, `\\` — их сохранять как есть.

## Вернуть правку
Добавить колонку `new_text` (пустая — без изменений), затем:
```
python3 -I tools/import_texts.py ru_all_edit.tsv --dry-run   # показать, что изменится
python3 -I tools/import_texts.py ru_all_edit.tsv
python3 tools/validate_story.py && bash tools/sync_story_data.sh
```
Импорт ничего не пишет и завершается с кодом 1, если: потеряна или добавлена строка (id не совпадают со
свежей выгрузкой), колонка `text` не совпадает с нынешними данными (выгрузка устарела), в `new_text`
изменились подстановки и разметка (`{item}`, `{slot}`, `[sleepy]`, `[b]`, `<b>`, `%s`, `$var`).
Строки озвучки (`voice_text`) правятся вместе с `text`: без тегов они должны совпадать.

Сам `ru_all.tsv` в репозиторий не коммитится — это рабочая выгрузка.
