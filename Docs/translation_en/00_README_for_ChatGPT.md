# «Дом пропавших дорог» → English: translation brief

Director's note (RU): ChatGPT, это все тексты игры для перевода на английский — 8 частей по ~250 строк, около 17 тыс. слов. Переводи по одной части за раз, в порядке номеров, и возвращай тот же TSV с заполненной колонкой `en`. Всё, что нужно знать, — ниже, по-английски.

## The game

A 2D point-and-click story game. Russian North, roughly 1900–1920s (no exact year). It is quiet and warm, a little sad, and never a fairy tale.

**Premise.** Agata, 18, studies in the district town. A year ago a flood took the bridge to her home village Olkhovka, across the river. Since then any boat sent across comes back to its own pier. She goes to her late aunt Dunya's house on the near bank (Zarechye) and finds that inside Olkhovka **twenty years** have passed while outside it was one year. Her mother Nina is now 67. Her brother Ilya, who was the younger one, is now 32, with an 8-year-old daughter, Ulyana. Through Dunya's old mirrors and objects Agata rebuilds the road so that it is "held from both ends". After that, time runs the same on both sides.

**Law of the world** (keep it consistent, it is quoted): «Вещи помнят место, которому служили. Дорогу держат с двух концов.» Suggested: *"Things remember the place they served. A road is held from both ends."*

Nothing lived is undone: no one gets younger, no resurrection. The tone is tender, practical and understated.

## Characters (voice and register)

| RU | EN (use exactly) | age | how they speak |
| --- | --- | --- | --- |
| Агата | Agata | 18 | young, observant, curious, stubborn, collected; feelings break through sometimes; light self-irony |
| Нина | Nina | 67 | Agata's mother, a village teacher: calm, precise, twenty years of tiredness without complaint |
| Илья (Илюша) | Ilya (Ilyusha — childhood pet form) | 32 | brother: gentle, businesslike, a carpenter |
| Ульяна (Уля) | Ulyana (Ulya) | 8 | Ilya's daughter: honest, lively, never cutesy |
| Варвара | Varvara | 31 | Ilya's wife; a few warm lines |
| Митя | Mitya | 37 | ferryman at the far pier: low voice, few words; boyish around his mother |
| Пелагея | Pelageya | 40 | boatwoman on the near pier, Mitya's mother: short, firm sentences, dry smile; sharp in danger, patient when helping |
| Павел | Pavel | 48 | miller: dry, careful, not a coward; worries about the mill pond |
| Тамара | Tamara | 53 | post-woman: chatty, practical, a smile in her voice; scolds and comforts in one breath |
| Фёдор Лукич | Fyodor Lukich | 70 | the old mill manager: businesslike, a little lost ("I meant to be back by morning") |
| Дуня / Евдокия | Dunya / Evdokia | † | Agata's aunt, Nina's sister; present only through her notes and things |
| Тихон | Tikhon | — | the stove-keeper: a small furry house spirit with cat-like habits, **not a cat and not a pet**. Grumpy, lazy, loves food, sarcastic, a self-important little official of the house. His humour is dry and deadpan. |
| Аксинья, Савелий | Aksinya, Savely | | villagers |

Places: Ольховка — **Olkhovka**, Заречье — **Zarechye**, the mill, the crossing, the far pier, the school, the gallery. Keep these exact names.

Forms of address:
- «мама» → *Mama*.
- «матушка» (Agata about her mother, more formal or old-fashioned) → *Mother*.
- «доченька» → *my girl* or *sweetheart*; never "daughter-dear".
- «тётя» → *Aunt* (Aunt Dunya).

## Rules

1. **Do not change the rows.** Keep `id` and every column as given; fill only `en`. One row in, one row out, same order. The file is TSV: no tab characters inside cells.
2. **`\n`** inside a cell is a line break. Keep it where it is. **`{n}`** and other `{…}` placeholders stay untouched.
3. **`[[слово|значение]]`** is glossary markup: an old word with a tooltip. In English write the plain natural word, without the markup. Example: `[[вестимо|конечно]]` → "of course".
4. **Quotes:** «…» → "…". Keep **— dashes** and **… ellipses** where they carry rhythm.
5. **Register.**
   - Plain, warm, slightly old-fashioned English. Avoid modern slang ("okay", "guys") and avoid fake-archaic "thee/thou".
   - Rural speech is shown by word choice and rhythm, not by misspellings.
   - Tikhon may be a bit more formal and pompous.
6. **Subtitles.** Spoken lines are shown under a Russian voice recording, so keep them about the same length as the Russian, never much longer.
7. **`max_len`.** If filled, the line is UI (button, label, item name). Stay within it.
8. **Columns that help you.**
   - `speaker` — who says it.
   - `scene_room` — the scene or room.
   - `context` — what it is or where it is shown.
   - `prev` — the line just before in the same scene.

   The prefix of the `id` says what kind of text it is:
   - `text:…` — examine texts, thoughts, UI;
   - `text:…#line` — the same text spoken as a character line;
   - `scene:…` — dialogue;
   - `quest:…` — side stories;
   - `item:…/name` — item names;
   - `loc:…/name` — place names;
   - `flag:…/desc` — journal facts, written in Agata's first person.
9. **Consistency.** Use the same English for the same Russian term across all parts: «Вещи помнят место…», «дорогу держат с двух концов», «сигналы», «живые» (the three-light signal = *"alive"*), the knot, the bracket, the plate, the ring.
10. **Uncertain lines.** If a line is ambiguous or a pun does not survive, still translate it. Then list it at the end of your answer as `id — problem — what you chose`.

## Return

Return the same TSV with the `en` column filled, one file per part (`en_part1_of8_done.tsv`, …). Under each file add the short list of uncertain lines.
