# Pylos Compass

Search for anything in World of Warcraft Forever, and see what is worth doing next.

For WoW Forever (Interface 16001). Needs no other addon. Pylos GatherInfo is optional: with it the tooltips of the search show where a trade good is gathered.

## Search

- Press the key (Alt+Space if it was free; change it in the options) and type a few letters. Enter opens the details of the marked result, Ctrl+Enter casts a spell or uses an item.
- The categories (spells, items, professions, NPCs, dungeons and raids, quests) can be hidden with a right-click on their tab; "Show all hidden" in the options brings them back.
- Filters, the details of an entry, where to find it and what it is for are in the entry's menu (Space).
- It learns what you choose for what you typed, and the recommendations what you do and how you answer them. "Learn from what I do" on the *Learning* page of the settings switches that off; its two Reset buttons forget what each part learned.
- It opens only out of combat.

## Recommendations

- A window with tabs (class, gear, professions, quests, supplies, dungeons, zones): what is worth doing now, and why.
- Hints: a quiet dot, a short note by the minimap or the same note with a sound, only for what matters and is new to you. Notes wait for a pause; an alert shows at once, except in a fight or on a flight. Each kind can be set to off, quiet, note or alert on its own page of the settings.
- A rating (good, bad, don't suggest) in each entry's menu teaches it what you want.

## Use

- **Left-click the minimap button** or `/pcompass`: the recommendations (while the button glows, first the new hint as a message you can rate). **Middle-click:** the search. **Right-click** or `/pcompass options`: the options (in the game options under *AddOns*, *Pylos Compass*).
- Both parts have a switch in the options; switched off, a part shows nothing, and its minimap click opens the other part. The game data stays loaded.
- Keys for the search and for the recommendations window are set under *Key Bindings*, *Pylos Compass*.

## Source layout

| Folder | Holds |
|---|---|
| `Kit\`, `UI\Kit\` | shared code of the Pylos addons: options page, saved variables, minimap button, widgets |
| `Core\` | namespace, events, maps, game state, background builder, saved data, the options page and the global API |
| `Data\` | generated game data; never edited by hand (see `SOURCES.md`) |
| `World\` | the game's domains (spells, items, NPCs, quests, ...) on top of `Data\`, and what is learned while playing |
| `You\` | the current character: zone, bags, quest log, flight points, hearthstone, class and ratings |
| `Engine\` | what is worth doing or looking up: reasons, memory, learning, the item valuer |
| `Search\` | the search bar: sources (one per category), links, filters, tools, UI |
| `Advice\` | the recommendations window and the hints |

`PylosCompass.toc` lists the files in load order, one block per folder.

## License

GPL-3.0-only. Where the data comes from is listed in `SOURCES.md`. World of Warcraft and its data belong to Blizzard Entertainment; this addon is not made or endorsed by Blizzard.
