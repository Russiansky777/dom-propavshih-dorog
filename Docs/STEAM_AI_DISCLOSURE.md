# Steam: раскрытие использования ИИ — черновик для анкеты содержимого

Зачем: в анкете содержимого Steam (Content Survey) разработчик обязан описать, как в игре использован ИИ: и заранее
сгенерированное содержимое («Any kind of content (art/code/sound/etc) created with the help of AI tools during
development»), и то, что генерируется во время игры. Источник: https://partner.steamgames.com/doc/gettingstarted/contentsurvey
(читано 12.11.2026). Текст из анкеты Valve показывает на странице игры в магазине.

Ниже — черновик по записи `Docs/ASSET_PROVENANCE.md`. **Это заявление от вашего имени: прочитайте и поправьте формулировки,
прежде чем вставлять.** Особенно первую строку про текст — как вы сами описываете свою работу с ChatGPT.

## Что сказать по-русски (суть)

- Сценарий и тексты написаны автором вместе с ChatGPT; английский перевод сделан ChatGPT.
- Фоны, слои, иконки предметов, интерфейс и листы персонажей сгенерированы в ChatGPT по брифам автора, затем отобраны,
  дорисованы и собраны в сцены.
- 3D-модели персонажей и большая часть их движений сгенерированы в Meshy, затем подогнаны и перенесены в игру.
- Голоса (русский и английский) синтезированы в ElevenLabs; часть звуковых эффектов — тоже.
- Музыка сгенерирована в Suno.
- 12 коротких роликов-петель («ожившие» картины ужина и объятий) сделаны из собственных картин игры моделью Kling
  (image-to-video).
- Код написан с помощью ИИ-помощников (Claude Code, Codex).
- Во время игры ИИ ничего не генерирует: всё содержимое готово заранее и одинаково у всех игроков.

## Текст для анкеты (английский, вставлять в поле о заранее сгенерированном содержимом)

> This game was made by a solo author working with AI tools at every stage, and all AI-made material was selected,
> edited and assembled by hand.
> - Story and text: written by the author together with ChatGPT; the English translation was made with ChatGPT.
> - 2D art (backgrounds, layers, item icons, interface art, character sheets): generated with ChatGPT image generation
>   from the author's briefs, then retouched and composited.
> - 3D characters and most of their animations: generated with Meshy, then adjusted, re-rigged where needed and
>   retargeted in the engine.
> - Voice acting (Russian and English): synthesized with ElevenLabs text-to-speech. Some sound effects were generated
>   with ElevenLabs as well.
> - Music: generated with Suno.
> - Twelve short looping video clips that bring painted scenes to life were made from the game's own paintings with
>   the Kling image-to-video model.
> - Code: written with AI coding assistants (Claude Code, Codex).

## Текст для поля о содержимом, которое генерируется во время игры

> None. The game does not generate any content with AI while it runs; everything the player sees and hears is
> pre-made and identical for every player.

## Что уточнить перед вставкой

1. Первая строка про сценарий — ваша формулировка авторства.
2. «Solo author» — если хотите иначе назвать себя или команду.
3. «Второй ИИ», сделавший стойки и жесты жителей 08.11 (`villagers_dialogue_game_patch_0811`): какой это сервис — в
   репозитории не записано; если он должен быть назван, добавьте строку.
4. Права на результат по каждому сервису — таблица «Права: что сверить» в `Docs/ASSET_PROVENANCE.md`.
