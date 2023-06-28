# Player Pings

This plugin allows players to point at the world and create a visual and audible ping that can be seen and heard by other players. 
The ping can be used to communicate locations, objectives, enemies, items, or anything else in the game world.

![image](https://github.com/dysphie/nmrih-ping-system/assets/11559683/d44a09e7-30cf-40f7-902a-aef0c336a607)

## Requirements
- [SourceMod 1.11](https://www.sourcemod.net/downloads.php?branch=stable) or higher
- (Optional) Client Preferences extension and plugin to allow players to hide pings (bundled and enabled with SourceMod by default)

## Installation
- Grab the latest ZIP from releases
- Extract the contents into `addons/sourcemod`
- Reload your translations: `sm_reload_translations` in server console
- Load the plugin: `sm plugins load player-pings`

## Configuration

You can configure the plugin by editing the following console variables in `cfg/sourcemod/player-pings.cfg`:

| Variable | Description | Default value |
| --- | --- | --- |
| sm_ping_enabled | Whether player pings are enabled | 1 | 
| sm_ping_cooldown_bucket_size | The maximum number of tokens you can have at any time. Sending a ping consumes one token. | 2 |
| sm_ping_cooldown_tokens_per_second | How many tokens, or fractions of a token players receive every second. The higher this value, the more pings you can send in a short time | 0.00833 |
| sm_ping_cooldown_shared | Whether the ping cooldown applies to all players or each player separately | 0 |
| sm_ping_text_height_offset | Vertically offsets the ping caption from its target position by a specified amount, in game units | 30.0 |
| sm_ping_color_r | The red color component for player pings | 10 |
| sm_ping_color_g | The green color component for player pings | 224 |
| sm_ping_color_b | The blue color component for player pings | 247 |
| sm_ping_distance_show | If true, shows distance to the ping location in the caption | 1 |
| sm_ping_distance_update_interval | How frequently the ping caption updates the distance to the ping location, in seconds. Be aware that lower values require more network traffic | 0.3 |
| sm_ping_distance_default_units | Default distance units for players without preference. 0 = Meters, 1 = Feet, 2 = Hammer units | 0 |
| sm_ping_color_randomize | If true, randomize the ping color for each player instead of using RGB variables | 1 |
| sm_ping_lifetime | The lifetime of player pings in seconds | 8 |
| sm_ping_range | The maximum reach of the player ping trace in game units | 3000 |
| sm_ping_icon | The icon used for player pings. Empty to disable | icon_interact |
| sm_ping_sound | The sound used for player pings | ui/hint.wav |
| sm_ping_circle_radius | Radius of the ping circle | 9.0 |
| sm_ping_circle_segments | How many straight lines make up the ping circle. More lines make the circle smoother, but they also use more network bandwidth and may not show up if the render limit is reached | 10 |
| sm_ping_players | Whether players can use pings to highlight other players | 0 |
| sm_ping_npcs | Whether players can use pings to highlight zombies | 0 |
| sm_ping_dead_can_use | Whether dead players can ping | 1 |
| sm_ping_text_location | Determines how the ping text is displayed. If set to 0, the ping text will appear on the screen at all times, and an arrow will point to the location of the ping. If set to 1, the ping text will only appear in the world when the player is looking at the location of the ping | 0 |
| sm_ping_limit | The maximum number of pings that can be active at a time | 3 |

## Usage

A.   Open the voice menu (Default: 3) and press the Use key (Default: E)

B.   Bind a key to the `sm_ping` command. For example:

```
bind mouse3 sm_ping
```

## Client Preferences

Players can toggle seeing pings via `sm_settings` -> `Player Pings`

## Overrides

This plugin supports the use of [overrides](https://wiki.alliedmods.net/Overriding_Command_Access_(Sourcemod)) 

- `ping_custom_duration` - Allows players to specify a custom duration argument for their ping, with the syntax `sm_ping <seconds>`
- `ping_cooldown_immunity` - Makes players immune to the cooldown system

## Translations

This plugin supports translations for different languages. This means that each player will see the ping text in their preferred language, as set by the `cl_language` console variable. You can edit the translations by modifying the `player-pings.phrases.txt` file in the `translations` folder. You can add new languages or change existing ones by following the [SourceMod Translation Wiki](https://wiki.alliedmods.net/Translations_(SourceMod_Scripting)).

## License

This plugin is licensed under the GNU General Public License v3.0 (GPLv3). This means you can use, modify, and distribute this plugin as long as you follow the terms and conditions of the license. You can find a copy of the license in the `LICENSE` file.
