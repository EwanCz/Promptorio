# Promptorio UI

The UI will split the screen in 2.
## Factory View
It display the factory as a up view on the left on the screen taking 80% on the screen.
The factory will be a tile map with some of them being minesite. On those site can be place miner which will extract the ressource.
In the center of the map is placed a collector it is where our ressource are sold.
The camera can be zoomed in/out and move in x/y axis. At startup it is zoomed out so the whole grid is visible (centered on an axis where the view is larger than the grid). While the player has not zoomed or panned, resizing the window keeps the whole grid in view. If the view is too small for the usual minimum zoom (0.4), the fit goes lower and that becomes the floor.

### Prototype machine placement
Machines are selected from the Build page or with keyboard shortcuts, then placed with a left click on an empty grid cell. Both ways enter the same placement mode and follow the same rules and costs. The shortcuts are Input Map actions (defined in `project.godot`, rebindable in Project Settings), bound by default to physical keys so the number row works on any layout (AZERTY included): `select_miner` (`1`), `select_smelter` (`2`), `select_assembler` (`3`), `select_conveyor` (`5`), `rotate_placement` (`R`, rotates the facing clockwise) and `cancel_placement` (`Escape`, clears the selection). The Collector is placed at the map center when the scene starts and has no select action, so it cannot be chosen for placement. Miners can only be placed on minesites.

A Smelter turns redder as it heats up (from 60° to the explosion at 150°); when it explodes it flashes, fades out with a burst of sparks and is destroyed, freeing its cell. No machine shows its name over it. The label over a machine is empty, except the Smelter's temperature (or BOOM once exploded) and a dot on a Conveyor that holds an item. A Conveyor shows its facing direction through its belt art (and the tooltip), with no arrow label over the machine; its status label is only a dot while it holds an item. It accepts one item and attempts to pass it to the adjacent machine in front after five simulation ticks. If that cell is empty or the machine refuses the item, the Conveyor holds the item and retries. Items can also move directly between adjacent machines (but two machines facing each other pass nothing to one another, so a smelter facing a conveyor that points back at it is blocked until one is rotated), so a Conveyor is only needed when the layout calls for a transport cell between machines.

## Bar
On the remaining 20% will be a Bar. This bar will contain mutiple page which can be swap by clicking the page marker at the top of the bar.
The different page are:
- Build: The list of buildable machines and their costs. See "Build page and economy" below.
- Chip Registry: List all the chips. The list will show the name of the chip. If you click on a chip it will display the `chip page` of the chip (More info on the `chip page` later). At the top of the page a `new chip` button is placed. It will open a blank chip page with the `name`="Blank", no `description` and no `prompt`.

## Chip Page
When a chip is clicked in the chip registry page. The game is paused and a popup happear at the center of the screen. It will contain the name of the selected chip, its description and its prompt. The prompt is what the llm receive. From this page we can edit/save/remove a chip.

## Machine tooltip
The Bar is split in two halves of equal height, with the Settings button below them at the very bottom:
- Top half: the page tabs (Build / Chip Registry) and the current page inside a scroll container, so a long list scrolls instead of growing the Bar.
- Bottom half: the machine tooltip, a panel of the Bar (not a popup over the map). It shows "Click a machine to see its details." until a machine is clicked. Clicking the same machine or an empty cell goes back to that hint. The details scroll when they do not fit. Show machine id, type, state, current action, connected chips with prompt preview and timeout (chip rows wrap to the narrow Bar), an add-chip picker from the registry, a log button, and the Rotate and Destroy actions.

The tooltip hides with the rest of the Bar (`E`).

### Build page and economy
Start with 100 money. These are MVP prices, kept together in the machine catalog used by both the Build page and placement:

| Machine | Cost |
| --- | ---: |
| Miner | 20 |
| Smelter | 30 |
| Assembler | 40 |
| Conveyor | 2 |

The Collector at the map center is provided for free and cannot be built or removed. The Build page always shows current money and each buildable machine's cost. Disable choices the player cannot afford. Selecting an affordable machine enters placement mode but does not charge money. Charge exactly once only when the machine is successfully placed. Invalid cells, occupied cells, miners placed off minesites, or insufficient money must leave both money and the machine registry unchanged. Keep the selected type active after a successful placement so the player can place several; `cancel_placement` (default Escape) exits placement mode. Show which type is selected and give clear feedback when placement is rejected.

### Machine actions
The machine tooltip panel provides the actions that apply to an existing machine:
- Rotate output: rotate `facing` clockwise (right, down, left, up) for Miner, Smelter, Assembler, and Conveyor. The Collector has no facing and shows no rotate action. Rotation changes where future output is sent; it does not alter stored items. The `rotate_placement` action (default R) rotates the next machine during placement; it also rotates the machine whose tooltip is open, so one press turns both the selected machine and the next placement (same as the Rotate button, nothing happens for the Collector).
- Remove: immediately free the machine's grid cell and remove it from the scene. Discard its stock, held item, and attached chips; refund half of its purchase price (`Placement.refund_for()`, rounded down: Miner 10, Smelter 15, Assembler 20, Conveyor 1), only when the player destroys it from the tooltip; a Smelter that explodes gives nothing. Do not offer removal for the fixed Collector. The freed cell can be rebuilt using normal placement checks and cost.

Tooltip current-action content:
- Miner: production rate (one ore per `mine_ticks`) and whether its output is blocked.
- Smelter / Assembler: recipe inputs and output, stock, idle/working/output-blocked state, and remaining craft time while working.
- Smelter additionally shows temperature and whether cooling is enabled.
- Conveyor: facing direction and whether it holds an item (and the item type when occupied).
- Collector: items sold and money earned.

Show machine state independently from current action: normal, down, or overheating. Refresh dynamic values from machine state/tick events rather than a UI simulation loop.

### Track C acceptance
- Build selection through the page and the existing Input Map actions results in the same placement mode and rules.
- A rejected placement never spends money; a successful placement spends the listed cost exactly once.
- Rotating and removing a placed machine through its tooltip updates routing and the grid registry correctly. The Collector remains fixed.
- The tooltip shows the current-action fields above and closes on same-machine/empty-cell selection.
- Page, popup, and tooltip controls consume their mouse input so clicks do not also place or select machines in the world.

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
The "Save / Load" button (Bar, below the Menu button and above Settings) opens `SaveDialog`, a popup that pauses the game like `ChipPage`. A name field and "Save" write a slot to `saves/<name>.json` (in the project folder in an editor run, `user://saves/` in an exported build); the list below shows each slot with its date, a "Load" and a "Delete" button. "Import a file..." and "Export to a file..." use the system file dialog to read or write a save anywhere on the disk. A successful load or import replaces the whole game and closes the dialog. Messages never show a path or the file content.
- Slot names: 40 characters at most, a valid file name, not starting with a dot.
- A refused file (bad JSON, wrong version, unknown machine type, cell outside the grid or taken, miner off a minesite, no Collector, ...) leaves the current game untouched and says why.
- The save embeds the chips its machines use. Loading overwrites a registry chip that has the same id (the save wins); a name already used by another chip gets a number appended.
- Not saved: requests in flight, chip cooldowns, chip logs. An exploding Smelter is left out.

### API key status
At the top of the Bar (above the page tabs), a colored `KeyStatus` panel reports the state of the selected provider's key. It is hidden for `mock`, which needs no key. States:
- Orange, "No active API key": neither a saved key nor a `.env` one (`Settings.needs_api_key()`).
- Grey, "Checking the API key...": a key exists and no verdict has arrived yet. Any settings change discards the previous verdict.
- Green, "API key verified.": the provider accepted the key.
- Red, "API key rejected (HTTP 401 ...)": the provider answered 401 or 403.
- Orange, "Could not verify the API key (...)": timeout, network failure, 429 or 5xx. This never says the key is wrong.

The verdict comes from `LLMManager.check_key()` (a free "list models" GET, so no tokens are spent), reported on `EventBus.key_checked(state, detail)`. `Main` runs it at startup and after every `settings_changed` (so after Settings save), and skips it in headless runs so tests never touch the network. Limits: it proves the key is accepted, not that the chosen model is available to it or that the account has credit. The panel lives in the Bar, so it hides with the Bar (`E`).

### Chip log
Open the selected machine's log from its tooltip. Show its most recent 200 log messages in order, update while open when new entries arrive, and provide a close button. Closing the log returns to the factory view without changing the selected machine or pausing simulation.
