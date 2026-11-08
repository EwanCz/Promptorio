# Promptorio UI

The UI will split the screen in 2.
## Factory View
It display the factory as a up view on the left on the screen taking 80% on the screen.
The factory will be a tile map with some of them being minesite. On those site can be place miner which will extract the ressource. The minesites are random: 4 groups of 3 touching tiles drawn at every game start, one of them always within 10 tiles of the Collector, and none closer than 5 tiles to it.
In the center of the map is placed a collector it is where our ressource are sold.
The camera can be zoomed in/out and move in x/y axis. At startup it is zoomed out so the whole grid is visible (centered on an axis where the view is larger than the grid). While the player has not zoomed or panned, resizing the window keeps the whole grid in view. If the view is too small for the usual minimum zoom (0.4), the fit goes lower and that becomes the floor.

### Prototype machine placement
Machines are selected from the Build page or with keyboard shortcuts, then placed with a left click on an empty grid cell. Both ways enter the same placement mode and follow the same rules and costs. The shortcuts are Input Map actions (defined in `project.godot`, rebindable in Project Settings), bound by default to physical keys so the number row works on any layout (AZERTY included): `select_miner` (`1`), `select_smelter` (`2`), `select_assembler` (`3`), `select_conveyor` (`5`), `rotate_placement` (`R`, rotates the facing clockwise) and `cancel_placement` (`Escape`, clears the selection). The Collector is placed at the map center when the scene starts and has no select action, so it cannot be chosen for placement. Miners can only be placed on minesites.

A Smelter turns redder as it heats up (from 60° to the explosion at 150°); when it explodes it flashes, fades out with a burst of sparks and is destroyed, freeing its cell. No machine shows its name over it. The label over a machine is empty, except the Smelter's temperature (or BOOM once exploded). A Conveyor that holds an item draws that resource's pixel icon (32x32, `ItemData.icon`) at the center of its cell. What a Smelter or an Assembler makes is put straight on the conveyor in front of it (at the center of the cell, no slide). An item handed over by another conveyor or a miner glides in from the center of the sender's cell to the center of the conveyor's during its five ticks, redrawn every frame from the part of the tick already gone (`GameState.tick_fraction()`), so a line of conveyors shows a continuous flow. A blocked item rests at the center. A Conveyor shows its facing direction through its belt art (and the tooltip), with no arrow label over the machine. It accepts one item and attempts to pass it to the adjacent machine in front after five simulation ticks. If that cell is empty or the machine refuses the item, the Conveyor holds the item and retries. Items can also move directly between adjacent machines (but two machines facing each other pass nothing to one another, so a smelter facing a conveyor that points back at it is blocked until one is rotated), so a Conveyor is only needed when the layout calls for a transport cell between machines.

## Bar
On the remaining 20% will be a Bar. This bar will contain mutiple page which can be swap by clicking the page marker at the top of the bar.
The different page are:
- Build: The list of buildable machines and their costs. See "Build page and economy" below.
- Chip Registry: List all the chips. The list will show the name of the chip. If you click on a chip it will display the `chip page` of the chip (More info on the `chip page` later). At the top of the page a `new chip` button is placed. It will open a blank chip page with the `name`="Blank", no `description` and no `prompt`.

## Chip Page
When a chip is clicked in the chip registry page. The game is paused and a popup happear at the center of the screen. It will contain the name of the selected chip, its description and its prompt. The prompt is what the llm receive. From this page we can edit/save/remove a chip.

## Visual feedback rule
Runtime status is shown with icons, not persistent text. Keep text where it carries content or meaning: machine and chip names, values and prices (the amount of money, the Smelter's temperature number), prompts, settings and necessary control labels. Every symbol that is not self-evident has a brief hover description (`tooltip_text`). Icons come from one pixel-art set (`Icons`, `scripts/ui/icons.gd`): 12x12 glyphs on colored badges, drawn at x2 with the nearest filter to match the 16 px machine art, and meaning is in the shape as well as the color. Static labels and text-entry screens (Settings, Chip Page, Chip Registry) are out of this rule. Decision bubbles are not part of the design.
- Chip activity above each machine (`ChipIndicator`, centered just above the machine's cell): an animated spinner while any attached chip waits for an answer, then briefly (1.5 s) one distinct icon for the last result: check (an action was applied), dash (no action), cross (failure or a rejected call). With several chips the spinner stays until all have answered, so one finishing chip never hides another that still runs.
- Production feedback at the corner of a producing machine's cell (`ProductionIndicator`, Miner/Smelter/Assembler only — `Machine.shows_production_feedback()`): green play while it is producing, red dash while its output is stalled (`Machine.get_production_state()`; a blocked delivery wins over producing), grey pause bars otherwise (switched off, or nothing to do right now). Unlike `ChipIndicator` it does not time out: it always shows the machine's current state, refreshed every tick, and carries no chip-call meaning. The machine tooltip's current-action row stays quiet while idle and shows the same blocked icon while stalled; while producing it adds a green play icon with the rate as a number (items per minute over the last 60 simulated seconds, `Machine.get_production_rate()`).
- Machine state in the details panel: one icon (green play: running, grey pause bars: paused, i.e. switched off, grey cross: down, orange flame: overheating) with the explanation on hover. Overheating and down win over paused, so a paused overheating machine still shows the flame (the hover adds "and paused"). The Conveyor and Collector ignore `enabled`, so they never show paused.
- API key in the Bar: a key icon plus a badge (see "API key status").
- Money and building choice on the Build page: coin icon plus amount, machine art plus cost number; no "Money" or "Miner - 20" text.
- Placement refusal in the Build page: a coin icon for insufficient funds, a red dash for any other refusal, reason on hover.
- Chip log: an icon timeline (see "Chip log").
- Miner prospecting / boost in the world: a small badge in the corner of the Miner's cell, hidden while it mines normally (see "Miner prospecting feedback on the map").

## Smelter heat feedback on the map
Besides the red tint, the Smelter art trembles as it approaches the 150° explosion: nothing below 100° (the overheating line), almost imperceptible until about 120°, a clear one near the end (at most 4 px on a 64 px cell, at 150°). It eases off as the Smelter cools and stops when it explodes. It moves the art only, never the machine or its cell. See `docs/PLAN.md`, "Smelter temperature".

## Miner prospecting feedback on the map
A Miner that is prospecting or boosted shows a small badge in a corner of its cell, separate from the chip indicator above it: a magnifying glass while prospecting (paused), a bolt while boosted (mining faster). It is hidden the rest of the time, while the Miner mines at its normal pace. See `docs/PLAN.md`, "Miner prospecting".

## Machine tooltip
The Bar is split in two halves of equal height, with one row of icon buttons below them (Menu, Resources, Machine tools, Save / Load, Settings):
- Top half: the page tabs (Build / Chip Registry) and the current page inside a scroll container, so a long list scrolls instead of growing the Bar.
- Bottom half: the machine details panel (`MachineTooltip`), a panel of the Bar (not a popup over the map). It shows "Select a machine" until a machine is clicked. Clicking the same machine or an empty cell goes back to that hint. The details scroll when they do not fit. Layout, top to bottom, with no section titles or explanatory text:
  - Header: the state icon (see "Visual feedback rule"), the title "<Type> #<id>", then icon buttons: log, rotate and destroy (rotate and destroy are hidden for machines that cannot use them, e.g. the Collector).
  - The current operation as icons and numbers, with a hover on each (resource art is shown at its 32 px size, badges at x2; hover names the resource). There is no "Working, X ticks left" text:
    - Craft machines: the recipe (each input resource with "xN" when it needs more than one, an arrow, the product), a progress bar for the current craft, and a stock row (each stored resource with its count; hidden when empty).
    - Miner: the mined resource, a clock icon with the ticks per unit, and a progress bar toward the next unit.
    - Conveyor: an arrow for its facing (right, down, left, up) and the carried resource, if any.
    - Collector: a coin with the money earned, a check with the items sold, and a refusal icon when it is not accepting.
    - Any machine whose output cannot be delivered gets a red blocked icon, a conveyor included: it is blocked once it has waited its move time and still cannot hand its item on (nothing in front, a head-on machine, or one that refuses it), and it clears when the item is delivered or removed or the belt is turned. The conveyor state sent to a chip carries `blocked` too. For a Miner, Smelter or Assembler this is the same badge as the in-world `ProductionIndicator` (see "Visual feedback rule"), with the production rate added as a number while it reads producing. Rows are rebuilt only when their content changes, so a hover in progress is not lost; the bar moves every tick. A Smelter adds one heat row: a thermometer icon that fills and turns green, orange, red as it heats up (hover: "Temperature (explodes at 150)"), the temperature as a number, and a snowflake icon that is lit when cooling is on and dim when off (hover: "Cooling on" / "Cooling off").
  - One block per attached chip: its name (hover shows the prompt), a clock icon with the timer in ticks, an "ask now" bolt button and a "remove" button. There are no state or event triggers: a chip is asked only by its timer or by "ask now".
  - Last, the chip picker with a plus button that attaches the picked chip.
  - Every icon button has a hover description: "Chip log", "Rotate", "Destroy this machine", "Ask the chip now", "Remove this chip", "Add the chosen chip", and the clock explains the timer. The panel stays narrow enough for the Bar: rows wrap, and long chip names are trimmed with an ellipsis (hover shows the prompt).
  - The buttons at the bottom of the Bar (Menu, Resources, Machine tools, Save / Load, Settings) all have the same format: a pixel icon only (house, gem, hammer, arrow into a tray, gear), no text, with the name as hover text ("Menu", "Resources", "Save / Load", "Settings"). They sit side by side in one row (`BarButtons`), right-aligned, in that order, so Settings stays at the right end.

The tooltip hides with the rest of the Bar (`E`).

### Build page and economy
Start with 100 money. These are MVP prices, kept together in the machine catalog used by both the Build page and placement:

| Machine | Cost |
| --- | ---: |
| Miner | 20 |
| Smelter | 30 |
| Assembler | 40 |
| Conveyor | 2 |

The Collector at the map center is provided for free and cannot be built or removed. The Build page always shows current money as a coin icon and the amount (hover: "Money") and, for each buildable machine, a button with the machine's own art and its cost as a number beside it (hover: the machine's name); the buttons wrap in a row. Disable choices the player cannot afford. Selecting an affordable machine enters placement mode but does not charge money. Charge exactly once only when the machine is successfully placed. Invalid cells, occupied cells, miners placed off minesites, or insufficient money must leave both money and the machine registry unchanged. Keep the selected type active after a successful placement so the player can place several; `cancel_placement` (default Escape) exits placement mode. Show which type is selected and give clear feedback when placement is rejected: an icon (coin for insufficient funds, a red dash otherwise) with the reason on hover, cleared when the player picks a type again.

### Destroy shortcut
`X` or `Delete` (`destroy_machine`) removes the machine shown in the details panel, like its Destroy button. It does nothing while any popup of the UI layer is open (Resources, Settings, Saves, Chip Page, Chip Log, the pause menu), so a key meant for a popup never deletes the machine behind it, and it never removes the Collector.

### Machine actions
The machine tooltip panel provides the actions that apply to an existing machine:
- Rotate output: rotate `facing` clockwise (right, down, left, up) for Miner, Smelter, Assembler, and Conveyor. The Collector has no facing and shows no rotate action. Rotation changes where future output is sent; it does not alter stored items. The `rotate_placement` action (default R) rotates the next machine during placement; it also rotates the machine whose tooltip is open, so one press turns both the selected machine and the next placement (same as the Rotate button, nothing happens for the Collector).
- Remove: immediately free the machine's grid cell and remove it from the scene. Discard its stock, held item, and attached chips; refund half of its purchase price (`Placement.refund_for()`, rounded down: Miner 10, Smelter 15, Assembler 20, Conveyor 1), only when the player destroys it from the tooltip; a Smelter that explodes gives nothing. Do not offer removal for the fixed Collector. The freed cell can be rebuilt using normal placement checks and cost.

Tooltip current-action content:
- Miner: effective production rate (ticks per unit, including the boost) and whether its output is blocked. While prospecting or boosted, an extra icon (magnifying glass / bolt) shows the ticks left in that span.
- Smelter / Assembler: recipe inputs and output, stock, idle/working/output-blocked state, and remaining craft time while working.
- Smelter additionally shows temperature and whether cooling is enabled.
- Assembler additionally shows its production mode (an icon, normal or fast) first in the recipe row; the recipe quantities shown are the active mode's (fast mode doubles each input).
- Conveyor: facing direction and whether it holds an item (and the item type when occupied).
- Collector: items sold and money earned.

Show machine state independently from current action: normal, down, or overheating. Refresh dynamic values from machine state/tick events rather than a UI simulation loop.

### Track C acceptance
- Build selection through the page and the existing Input Map actions results in the same placement mode and rules.
- A rejected placement never spends money; a successful placement spends the listed cost exactly once.
- Rotating and removing a placed machine through its tooltip updates routing and the grid registry correctly. The Collector remains fixed.
- The tooltip shows the current-action fields above and closes on same-machine/empty-cell selection.
- Page, popup, and tooltip controls consume their mouse input so clicks do not also place or select machines in the world.

### Resources page
The Resources button of the Bar opens a popup at the center of the screen (it does not pause the game). It lists every resource of the catalog (`data/items.tres`) in a scrollable table: name, the machine that builds it, what it needs (`Mined` for a raw resource, else e.g. `1 Silver Bar + 2 Redstone`), the mining or build time in ticks and the price the Collector pays. Close hides it. The table is read from `ItemCatalog` when the popup is created, so a new resource appears without touching the UI. Example chains: 2 coal make power in a Smelter, a silver bar (smelted silver) + 2 redstone make a circuit in an Assembler, and a steel + a circuit + power make a gun.

### Machine tools page
The hammer button of the Bar opens a popup (`ToolsPage`, it does not pause the game) that lists, for each type of machine in build order (Miner, Smelter, Assembler, Collector, Conveyor), every tool a chip may call on it: the signature with the argument types and ranges (`set_mine_ticks(ticks: integer 20..100)`, `discard_stock(item: string (one of 16), count: integer 1..10)`) and its description. It is read from each machine's own `get_tool_schemas()` when the popup is created, so a new tool appears without touching the UI. The shared `set_enabled` is listed under every type.

### Settings dialog
Open Settings from the Bar. Offer `mock`, `anthropic`, and `openai` providers. For providers that use credentials, show that provider's API key field and model picker; mask the key while editing. The `mock` provider needs neither. Save writes through `Settings.save_settings()` and closes the dialog; Close dismisses without saving pending edits. If the provider's key comes from `.env` (`Settings.get_key_source()`), the key field stays empty and its placeholder says so; saving never copies the `.env` key to disk, and saving an empty field falls back to it. Never print or log the key.

For `anthropic` and `openai`, an optional "Base URL" field (blank by default, saved per provider) lets the player use a compatible relay; it takes precedence over the editor-only `ANTHROPIC_BASE_URL` / `OPENAI_BASE_URL` environment and .env overrides (see "Provider base URL" in `CLAUDE.md`). A malformed value is not blocked in the dialog: the Bar's key status reports that the base URL is invalid and nothing is sent.

### Main menu
The game starts on `scenes/menu/main_menu.tscn` (`run/main_scene`), not on the factory. Buttons, top to bottom: Play, Load Game, Chips, Options, Exit (no Credits). Each is a `PixelButton` (`scripts/ui/pixel_button.gd`) drawn with the pack art (`assets/pixel_art_buttons_pack/btn_<name>_{normal,hover,pressed}@8x.png`, 64x16 art shown 4x bigger, label included in the image).
- Play: `GameState.reset()` (starting money, clock at 0) then the game scene.
- Load Game: the `SaveDialog` in menu mode (`use_as_menu()`): slots of `saves/` with Load / Delete, plus "Import a file...", no Save row and no Export, no pause. A picked save is fully validated (`SaveGame.validate(null, data)`), stored in `SaveGame.pending`, and the game scene restores it when it starts. A refused file keeps the player in the menu with the reason.
- Chips: `ChipManager` popup (the Chip Registry list with "New chip") and the same `ChipPage` popup as in game, to prepare chips before playing. They are saved to `user://chip_registry.tres` like in game.
- Options: the `SettingsDialog`. Exit quits.
- Art still missing: the Chips button has no image in the pack yet, so it shows a text label in the pack's colors. Dropping `btn_chips_normal@8x.png`, `btn_chips_hover@8x.png` and `btn_chips_pressed@8x.png` in `assets/pixel_art_buttons_pack/` makes it use them with no code change.

### Pause menu
The "Menu" button of the Bar, or `cancel_placement` (Escape) when no machine type is selected, opens `PauseMenu` (a popup that pauses the game like `ChipPage`; Escape closes it). Resume closes it, Restart starts a new game (`GameState.reset()`, scene reloaded), Main Menu goes back to the start screen. Nothing is saved automatically: the menu says unsaved progress is lost. Art: `assets/pixel_ui_pack/pause_{resume,restart,main_menu}_*@8x.png`.

### Save / Load dialog
The "Save / Load" button (Bar, below the Menu button and above Settings) opens `SaveDialog`, a popup that pauses the game like `ChipPage`. A name field and "Save" write a slot to `saves/<name>.json` (in the project folder in an editor run, `user://saves/` in an exported build); the list below shows each slot with its date, a "Load" and a "Delete" button. "Import a file..." and "Export to a file..." use the system file dialog to read or write a save anywhere on the disk. A successful load or import replaces the whole game (machines, money, and the minesites of the map) and closes the dialog. Messages never show a path or the file content.
- Slot names: 40 characters at most, a valid file name, not starting with a dot.
- A refused file (bad JSON, wrong version, unknown machine type, cell outside the grid or taken, miner off a minesite, no Collector, ...) leaves the current game untouched and says why.
- The save embeds the chips its machines use. Loading overwrites a registry chip that has the same id (the save wins); a name already used by another chip gets a number appended.
- Not saved: requests in flight, chip cooldowns, chip logs. An exploding Smelter is left out.

### API key status
At the top of the Bar (above the page tabs), the `KeyStatus` panel reports the state of the selected provider's key as a key icon with a badge; hovering either shows the explanation. It is hidden for `mock`, which needs no key. States:
- Orange "!" badge, "No active API key...": neither a saved key nor a `.env` one (`Settings.needs_api_key()`).
- Animated spinner badge (it turns while the check is pending and stops at the verdict), "Checking the API key...": a key exists and no verdict has arrived yet. Any settings change discards the previous verdict.
- Green check, "API key verified.": the provider accepted the key.
- Red cross, "API key rejected (HTTP 401 ...)": the provider answered 401 or 403.
- Orange "?", "Could not verify the API key (...)": timeout, network failure, 429 or 5xx, or an invalid base URL. This never says the key is wrong.

The verdict comes from `LLMManager.check_key()` (a free "list models" GET, so no tokens are spent), reported on `EventBus.key_checked(state, detail)`. `Main` runs it at startup and after every `settings_changed` (so after Settings save), and skips it in headless runs so tests never touch the network. Limits: it proves the key is accepted, not that the chosen model is available to it or that the account has credit. The panel lives in the Bar, so it hides with the Bar (`E`).

### Chip log
Open the selected machine's log from its tooltip. It is a compact timeline of icons, oldest first, wrapping and scrolling, holding the machine's most recent 200 entries; new entries appear while it is open. It has a close button; closing returns to the factory view without changing the selected machine or pausing the simulation. There is no log text: hovering an icon shows a short plain-language explanation, never raw trigger names, tool names or JSON.
- Spinner: "Checking: <chip name>", a chip asked the LLM.
- Green check: an applied call says what was set, e.g. "Cooling set on", "Machine set to paused", "Mining pace set to 40 ticks per ore". It says what was set, not that something changed, because the call may have been a no-op. A conveyor turn names its direction: "Direction set to right / down / left / up".
- Grey dash: "No action", a successful answer without tool calls.
- Red cross: "Request failed", or "Action rejected" for a call the machine refused.
- Blue dot: any other message, shown as is (e.g. "exploded at 150°").

The technical messages (trigger reason, tool call with its arguments, error details) are written unchanged to the session log. The translation happens only in `ChipLog`; `Machine.log_chip` and the session log are untouched.
