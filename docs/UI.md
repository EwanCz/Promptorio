# Promptorio UI

The UI will split the screen in 2.
## Factory View
It display the factory as a up view on the left on the screen taking 80% on the screen.
The factory will be a tile map with some of them being minesite. On those site can be place miner which will extract the ressource.
In the center of the map is placed a collector it is where our ressource are sold.
The camera can be zoomed in/out and move in x/y axis.

## Bar
On the remaining 20% will be a Bar. This bar will contain mutiple page which can be swap by clicking the page marker at the top of the bar.
The different page are:
- Build: The list of every build the user can do with the cost it make them in money.
- Prompt Registry: List all the prompt config. The list will show the name of the prompt. If you click on a prompt it will display the `prompt page` of the prompt (More info on the `prompt page` later). At the top of the page a `new prompt` button is placed. It will open a blank prompt page with the `name`="Blank", no `description` and no `message`.

## Prompt Page
When a prompt is cliked in the prompt registry page. The game is paused and a popup happear at the center of the screen. It will contain the name of the selected prompt, it's description and it's message. The message is what the llm receive. From this page we can edit/save/remove a prompt.

## Machine tooltop
When clicked on a machine a tooltip open. Close if click again. The tooltip display the machine id, type (ex: smelter), each chip connected to it (a machine can have several) with its prompt and the timeout between each call, an add button to add a chip by picking a prompt from the `prompt registry` , a log button to open the `log page`, the current action (miner have the ressource prodution rate, smelter/assembler have what is consume for which ressource and how long is remaining, etc...) and the states (ex: normal/down/overheating)
