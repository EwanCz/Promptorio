# Promptorio UI

The UI will split the screen in 2.
## Factory View
It display the factory as a up view on the left on the screen taking 80% on the screen.
The factory will be a tile map with some of them being minesite. On those site can be place miner which will extract the ressource.
In the center of the map is placed a collector it is where our ressource are sold.
The camera can be zoomed in/out and move in x/y axis.

### Prototype machine placement
Machines are selected from the Build page or with keyboard shortcuts, then placed with a left click on an empty grid cell. Both ways enter the same placement mode and follow the same rules and costs. The shortcuts are Input Map actions (defined in `project.godot`, rebindable in Project Settings), bound by default to physical keys so the number row works on any layout (AZERTY included): `select_miner` (`1`), `select_smelter` (`2`), `select_assembler` (`3`), `select_conveyor` (`5`), `rotate_placement` (`R`, rotates the facing clockwise) and `cancel_placement` (`Escape`, clears the selection). The Collector is placed at the map center when the scene starts and has no select action, so it cannot be chosen for placement. Miners can only be placed on minesites.

A Conveyor uses the facing direction shown by its status label. It accepts one item and attempts to pass it to the adjacent machine in front after five simulation ticks. If that cell is empty or the machine refuses the item, the Conveyor holds the item and retries. Items can also move directly between adjacent machines, so a Conveyor is only needed when the layout calls for a transport cell between machines.

## Bar
On the remaining 20% will be a Bar. This bar will contain mutiple page which can be swap by clicking the page marker at the top of the bar.
The different page are:
- Build: The list of buildable machines and their costs. See "Build page and economy" below.
- Chip Registry: List all the chips. The list will show the name of the chip. If you click on a chip it will display the `chip page` of the chip (More info on the `chip page` later). At the top of the page a `new chip` button is placed. It will open a blank chip page with the `name`="Blank", no `description` and no `prompt`.

## Chip Page
When a chip is clicked in the chip registry page. The game is paused and a popup happear at the center of the screen. It will contain the name of the selected chip, its description and its prompt. The prompt is what the llm receive. From this page we can edit/save/remove a chip.

## Machine tooltop
When clicked on a machine a tooltip opens. Clicking the same machine or an empty cell closes it. Show machine id, type, state, current action, connected chips with prompt preview and timeout, an add-chip picker from the registry, and a log button.

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
The machine tooltip provides the actions that apply to an existing machine:
- Rotate output: rotate `facing` clockwise (right, down, left, up) for Miner, Smelter, Assembler, and Conveyor. The Collector has no facing and shows no rotate action. Rotation changes where future output is sent; it does not alter stored items. The `rotate_placement` action (default R) rotates the next machine during placement; with no build type picked it rotates the machine whose tooltip is open instead (same as the Rotate button, nothing happens for the Collector).
- Remove: immediately free the machine's grid cell and remove it from the scene. Discard its stock, held item, and attached chips; do not refund its purchase price. Do not offer removal for the fixed Collector. The freed cell can be rebuilt using normal placement checks and cost.

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
Open Settings from the Bar. Offer `mock`, `anthropic`, and `codex` providers. For providers that use credentials, show that provider's API key field and model picker; mask the key while editing. The `mock` provider needs neither. Save writes through `Settings.save_settings()` and closes the dialog; Close dismisses without saving pending edits. If the provider's key comes from `.env` (`Settings.get_key_source()`), the key field stays empty and its placeholder says so; saving never copies the `.env` key to disk, and saving an empty field falls back to it. Never print or log the key.

### Chip log
Open the selected machine's log from its tooltip. Show its most recent 200 log messages in order, update while open when new entries arrive, and provide a close button. Closing the log returns to the factory view without changing the selected machine or pausing simulation.
