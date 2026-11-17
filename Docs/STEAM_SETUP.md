# Steam: что ввести в Steamworks (для Директора)

Директор 16.11: «так надо чтобы и достижения и оверлей и сохранения». Со стороны игры сделано (16.11): GodotSteam,
SteamService, достижения по следам выборов, лицензия на экране «Лицензии». Ниже — что нужно сделать на сайте Steamworks,
когда будет приложение (AppID). Всё, что здесь не названо, делаю я.

## 1. Номер приложения (AppID)
Появляется после оплаты Steam Direct (100 $ за игру; для бесплатной игры не возвращается — возврат только после 1 000 $
выручки) и проверки банка, налогов и личности (15–30 дней): https://partner.steamgames.com/steamdirect.
**Пришлите номер в чат** — это не секрет. Я впишу его в `game/data/steam.json`.

## 2. Облачные сохранения (Steam Cloud, без кода)
Steamworks → приложение → **Application → Steam Cloud** (https://partner.steamgames.com/doc/features/cloud):
- Byte quota per user: `10000000` (10 МБ; одно сохранение игры — 3–8 КБ, слотов около десятка), Number of files allowed per user: `100`.
- **Auto-Cloud → Root Paths → Add New Path:**
  - Root: `WinAppDataRoaming`
  - Subdirectory: `Godot/app_userdata/Dom propavshih dorog/saves`
  - Pattern: `*.json`
  - OS: Windows
  - Recursive: нет
- Сохранить, затем **Publish** (вкладка Publish) — без публикации настройки не действуют.

Почему так: игра хранит сохранения в `%APPDATA%\Godot\app_userdata\Dom propavshih dorog\saves\` (так делает движок Godot:
https://docs.godotengine.org/en/stable/tutorials/io/data_paths.html). Настройки (громкость, язык) в облако не идут — это
настройки компьютера, Valve советует их не переносить. Steam Deck запускает Windows-сборку через Proton — эта же папка.

## 3. Достижения
Steamworks → **Stats & Achievements → Achievements** (https://partner.steamgames.com/doc/features/achievements).
Для каждого — «New Achievement»:
- **API Name** — строго как в таблице «В Steam — 8» `Docs/STEAM_ACHIEVEMENTS.md` (`ACH_DAY1`, `ACH_Q02`…): по этому
  имени игра сообщает Steam, что достижение открыто.
- Display Name (название) и Description (описание) — на русском и английском (Steamworks даёт вкладки языков).
- Две иконки: открыто и закрыто.
- Set By: `Client`. Hidden — по желанию (скрытые не показывают описание до получения).
- Затем **Publish**.

Состав — 8 (ваше решение 17.11). Осталось утвердить: английские названия, описания, иконки (черновики — в той же таблице).

## 4. Сборка в Steam
Папка для Steam — три файла: `DomPropavshihDorog.exe` и рядом `libgodotsteam.windows.template_release.x86_64.dll`,
`steam_api64.dll`. Launch Options (Installation → General): Executable `DomPropavshihDorog.exe`, OS Windows. Выгрузка
(SteamPipe, https://partner.steamgames.com/doc/sdk/uploading) — когда будет AppID: вместе решим, кто выгружает — я через
сборочный аккаунт (логин и пароль только в секретах GitHub, не в чате) или вы через SteamPipe GUI.

## Проба оверлея до своего AppID (по желанию)
С ближайшей сборкой в релизе появится `steam_proba_overlay.zip`: две библиотеки и `steam_appid.txt` с номером 480 —
это тестовое приложение Valve «Spacewar». Распаковать рядом с exe, открыть Steam, запустить exe → Shift+Tab открывает
оверлей Steam поверх игры (в нём будет написано «Spacewar» — так и должно быть). Достижения так не проверить — они
появятся только в своём приложении. Без этих файлов рядом игра работает как раньше.
