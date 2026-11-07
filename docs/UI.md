# Promptorio UI

The UI will split the screen in 2.
## Factory View
It display the factory as a up view on the left on the screen taking 80% on the screen.
The factory will be a tile map with some of them being minesite. On those site can be place miner which will extract the ressource.
In the center of the map is placed a collector it is where our ressource are sold.
The camera can be zoomed in/out and move in x/y axis.

### Prototype machine placement
Until the Build page is connected, machines are selected with keyboard shortcuts and placed with a left click on an empty grid cell. These shortcuts are Input Map actions (defined in `project.godot`, rebindable in Project Settings), bound by default to physical keys so the number row works on any layout (AZERTY included): `select_miner` (`1`), `select_smelter` (`2`), `select_assembler` (`3`), `select_collector` (`4`), `select_conveyor` (`5`), `rotate_placement` (`R`, rotates the facing clockwise) and `cancel_placement` (`Escape`, clears the selection). The Collector is placed at the map center when the scene starts. Miners can only be placed on minesites.

A Conveyor uses the facing direction shown by its status label. It accepts one item and attempts to pass it to the adjacent machine in front after five simulation ticks. If that cell is empty or the machine refuses the item, the Conveyor holds the item and retries. Items can also move directly between adjacent machines, so a Conveyor is only needed when the layout calls for a transport cell between machines.

## Bar
On the remaining 20% will be a Bar. This bar will contain mutiple page which can be swap by clicking the page marker at the top of the bar.
The different page are:
- Build: The list of every build the user can do with the cost it make them in money.
- Chip Registry: List all the chips. The list will show the name of the chip. If you click on a chip it will display the `chip page` of the chip (More info on the `chip page` later). At the top of the page a `new chip` button is placed. It will open a blank chip page with the `name`="Blank", no `description` and no `prompt`.

## Chip Page
When a chip is clicked in the chip registry page. The game is paused and a popup happear at the center of the screen. It will contain the name of the selected chip, its description and its prompt. The prompt is what the llm receive. From this page we can edit/save/remove a chip.

## Machine tooltop
When clicked on a machine a tooltip open. Close if click again. The tooltip display the machine id, type (ex: smelter), each chip connected to it (a machine can have several) with its chip prompt and the timeout between each call, an add button to add a chip by picking a chip from the `chip registry` , a log button to open the `log page`, the current action (miner have the ressource prodution rate, smelter/assembler have what is consume for which ressource and how long is remaining, etc...) and the states (ex: normal/down/overheating)
