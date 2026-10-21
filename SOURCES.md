# Pylos Compass: sources

Pylos Compass is free software under the GNU General Public License, version 3
(`LICENSE`). Its data files (`Data\`)
are generated from the sources below by scripts kept outside the addon; the
header of each file names its own sources.

## Blizzard Entertainment's game data

World of Warcraft, its game data and its names (of items, spells, NPCs,
quests, zones and the rest), its texts and its art are the property of
Blizzard Entertainment, Inc. They are not covered by the GNU General Public
License of this addon, which applies only to the addon's own work. They are
used here, as every interface add-on uses the game client's data, for a free
user interface add-on of World of Warcraft. This addon is not made or
endorsed by Blizzard Entertainment.

## The game client's tables (WoW Forever)

DB2 tables of the client, read as CSV from [wago.tools](https://wago.tools/db2)
(builds 1.60.1.70291 to 1.60.1.70450, as each data file's header says):
ItemSparse, Item, ItemClass/ItemSubClass, ItemEffect, ItemXItemEffect,
ItemArmor*, ItemDamage*, RandPropPoints, ArmorLocation, SpellEffect,
SpellReagents, SpellLevels, SpellName, SpellMisc, SpellDuration, SkillLine,
SkillLineAbility, SkillRaceClassInfo, TraitDefinition, Map, MapDifficulty,
Difficulty, GroupFinderActivity, DungeonEncounter, AreaTrigger, AreaTable,
UiMap, UiMapAssignment, UiMapXMapArt, WorldMapOverlay, TaxiNodes, TaxiPath,
TaxiPathNode, TransportAnimation, QuestXP, QuestFactionReward, QuestSort,
ChrClasses, Faction, FactionTemplate, Holidays, Lock.
Files: ItemNames_enUS, ItemFacts, ItemStats, ClassSpells,
ProfessionSpells, OtherRecipes, Dungeons_enUS, NPCPlaces, TravelNet,
QuestFacts, Gathering (Lock: the skill a node needs; UiMap and
UiMapAssignment: the nodes' zones), Events (Holidays: the calendar's names),
NPCFacts (Faction, FactionTemplate). ItemNames_enUS, ItemFacts, ItemStats and
ItemPrices also use the client's hotfix rows of ItemSparse
(`Cache\ADB\enUS\DBCache.bin`).

The client's caches of the server's answers (`Cache\WDB\enUS\creaturecache.wdb`,
build 70450; `questcache.wdb`, build 70291) and what the game answered the author's private
collecting tool (NPC names and titles, item facts and stats of items the
tables lack): NPCNames_enUS, NPCFacts, QuestNames_enUS, QuestFacts,
ItemNames_enUS, ItemFacts, ItemStats.

## vmangos (1.12 data)

The [vmangos](https://github.com/vmangos/core) world database (db_latest
2026-09-28), licensed GPL-2.0-or-later: the NPCs' levels, roles, reaction and
zones (NPCFacts), their spawns (NPCPlaces), what they drop and sell
(NPCLinks), dungeon entrances (Dungeons_enUS), and who gives and takes
each quest and what it needs first (QuestLinks), and where gathered
materials come from (Gathering: creature_template, creature,
creature_loot_template, reference_loot_template, skinning_loot_template,
gameobject_template, gameobject, gameobject_loot_template, item_template),
and which NPCs and quests come
only with a world event such as Feast of Winter Veil (Events: game_event,
game_event_creature, game_event_quest; whether an event runs comes from
the game's calendar or its NPCs seen), which flight paths connect
(TravelNet: taxi_path_transitions, gameobject, gameobject_template,
transports) and which trainers teach a recipe that needs a specialization
(ProfessionSpells: npc_trainer). Used only where the game
itself does not tell; what is seen in play replaces it (below). Where a
level, role, zone, dungeon entrance, drop, ware, quest giver or taker is
still the 1.12 data's, the addon marks it "unchecked".

vmangos is licensed under the GNU General Public License, version 2 or (at
your option) any later version (GPL-2.0-or-later). Its copyright lines, as
its source files give them:

    Copyright (C) 2005-2011 MaNGOS <http://getmangos.com/>
    Copyright (C) 2009-2011 MaNGOSZero <https://github.com/mangos/zero>
    Copyright (C) 2011-2016 Nostalrius <https://nostalrius.org>
    Copyright (C) 2016-2017 Elysium Project <https://github.com/elysium-project>

and the vmangos contributors (https://github.com/vmangos/core). Thanks to
all of them.

## Carbonite (zone connections)

`Data\Paths.lua`, the walkable crossings between zones and which side may take a transport, is taken from
[Carbonite](https://github.com/IrcDirk/Carbonite-All-in-One-Retail-Classic) (`Carbonite/Data/camelot/ZoneConnections.lua`,
commit 5c7646f022, 2026-09-25), licensed under the GNU General Public License, version 3.

## WhatsTraining (class trainers)

`D.trainCosts` in `Data\ClassSpells.lua`, the class trainers' spells and
their cost, are taken from [WhatsTraining](https://www.curseforge.com/wow/addons/whatstraining)
11.0.0-beta21 (`Classes/Camelot/*.lua`) by Sveng (its TOC's author; the
copyright line of its LICENSE names no one), MIT License. The list also
tells which spells Forever's trainers teach before a trainer was seen.
Thanks to its authors. Its license, as its `LICENSE` file gives it:

```
MIT License

Copyright (c) 2019

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Common player usage (dungeon short names)

The short names a search finds dungeons by ("bfd", "lbrs ubrs", "dm" for
Deadmines and Dire Maul, `SHORT_NAMES` in `World\Dungeons.lua`, the field
`searchWords`) are the abbreviations players commonly use in chat and the
group finder, as Wowpedia's lists of abbreviations give them; only for the
instances in the data.

## Left out of the data

Test and placeholder NPCs, items and quests are left out by name (the
generators' hand fixes, each with its evidence). Also left out:

- test NPCs ("World ..." trainers and vendors, "Mage 20", titles with UNUSED,
  NYI, PTR) and NPCs without a role named like an item (summoned pets and
  mounts, herb-node placeholders), each only where no 1.12 spawn, no quest
  relation and no sighting in play shows them real;
- rank spells named like their profession that teach no skill (not recipes);
- unused variants of an item that has a used one of the same name, item class
  and use (sold, dropped, made or named by a quest);
- the second "Naxxramas" (map 2921, no group browser row: the raid 533 stays).

## The engine's own numbers

The stat weights of the item valuer (`Engine\ItemValue\Weights.lua`) are made
for this addon from the classic formulas (no other addon's scales).

## Numbers checked against other addons (no data copied)

- Flight speed (30 yards a second, `World\Routes.lua`): checked against the
  flight times measured by [Leatrix Plus](https://www.leatrix.com/)
  (`Leatrix_Plus_Flight_Alliance/Horde.lua`), 185 direct flights.
- Ship speed (rough): checked against the round trips of
  [Nauticus](https://github.com/droolio/Nauticus) (`data.lua`).
- Ride times of boats and zeppelins (`Data\TravelNet.lua`): computed with the
  path model of TrinityCore's `TransportMgr::GeneratePath` (no code copied)
  and checked against vmangos' `transports.period`.
- Hit caps of the item valuer (`Engine\ItemValue\Value.lua`: 5 % and 4 % against
  equal-level foes, 8 % and 17 % against raid bosses, 19 % more for melee
  with a weapon in the off hand): the client's own hit cap texts
  (`CR_*_HIT_CAP_TOOLTIP`, GlobalStrings) and the client's
  `DUAL_WIELD_HIT_PENALTY`, checked against Method's guide
  [How Does Hit Chance Work in WoW Forever?](https://www.method.gg/wow-forever/how-does-hit-chance-work-in-wow-forever)
  (6 October 2026). Where they differ (its 29 % for dual wielding against
  bosses, the client's 8 + 19 = 27 %) the client counts.

## Learned while you play

What the game shows while you play is kept in `PylosCompassWorldDB` on your own
computer only and counts before the data files: NPCs met and their zones,
places, roles, wares, levels and drops (`World\LearnNPCs.lua`, with wares of limited stock), quest givers
and takers and daily or weekly quests, also from an NPC's quest list
(`World\LearnQuests.lua`), what trainers list and each service's level,
skill and cost (`World\LearnTrainers.lua`), crossings between zones walked
(`World\LearnCrossings.lua`), vendors' prices where the data is wrong and
each vendor's discount (`World\Prices.lua`), dungeon
entrances (`World\Dungeons.lua`), which world events run (`World\Events.lua`),
your flight points (`You\Taxi.lua`), your hearthstone and mount speed
(`You\Hearth.lua`). Nothing is sent anywhere.

`Data\Seen.lua` is the same kind of knowledge, seen while the author played
WoW Forever, shipped with the addon: it counts as seen for everyone, before
the 1.12 data, and what you see yourself counts before it.

## The game's interface (the search and the recommendations window)

What the search and the window take from the WoW Forever client, build 1.60.1:

- atlas names and texture file IDs of the game's own interface (the micro
  menu's symbols, the professions' backgrounds and bars, the group finder's
  pictures), looked up in the client's DB2 tables `UiTextureAtlasMember`,
  `UiTextureAtlas` and `ManifestInterfaceData`, read as CSV from
  https://wago.tools; the crops of the micro menu symbols measured in their
  texture files;
- the game's API and global strings at run time.

## Links

Wowhead links point to https://www.wowhead.com/forever/ (no data is taken
from Wowhead).
