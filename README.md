# Player Pings

This plugin allows players to point at the world and create a visual and audible ping that can be seen and heard by other players. 
The ping can be used to communicate locations, objectives, enemies, items, or anything else in the game world.

![image](https://github.com/dysphie/nmrih-ping-system/assets/11559683/d44a09e7-30cf-40f7-902a-aef0c336a607)

## Features

- Customizable ping icon, color, sound, lifetime, and size
- Cooldown system to prevent spamming
- Option to disable pinging players or NPCs
- Option to allow dead players to ping

## Installation
- Grab the latest ZIP from releases
- Extract the contents into `addons/sourcemod`
- Relaod your translations: `sm_reload_translations` in server console
- Load the plugin: `sm plugins load player-pings`

## Optional requirements
- The Client Preferences extension to allow players to hide pings via `sm_settings`

## Configuration

You can configure the plugin by editing the following console variables in `cfg/sourcemod/player-pings.cfg`:

| Variable | Description | Default |
| --- | --- | --- |
| sm_ping_enabled | Whether player pings are enabled | 1 |
| sm_ping_cooldown_tokens_per_second | Tokens added to the bucket per second | 0.05 |
| sm_ping_cooldown_bucket_size | Number of command tokens that fit in the cooldown bucket | 3 |
| sm_ping_icon_height_offset | Offset ping icon from ping position by this amount | 30.0 |
| sm_ping_color_r | The red color component for player pings | 10 |
| sm_ping_color_g | The green color component for player pings | 224 |
| sm_ping_color_b | The blue color component for player pings | 247 |
| sm_ping_lifetime | The lifetime of player pings in seconds (max 25.6) | 8 |
| sm_ping_trace_width | The width of the player ping trace in game units | 20 |
| sm_ping_range | The maximum reach of the player ping trace in game units | 32000 |
| sm_ping_icon | The icon used for player pings. Empty to disable | icon_interact |
| sm_ping_sound | The sound used for player pings | ui/hint.wav |
| sm_ping_circle_radius | Radius of the ping circle | 9.0 |
| sm_ping_circle_segments | How many straight lines make up the ping circle | 10 |
| sm_ping_players | Whether pings can target other players | 0 |
| sm_ping_npcs | Whether pings can target zombies | 0 |
| sm_ping_dead_can_use | Whether dead players can ping | 1 |

## Usage

A.   Open the voice menu (Default: 3) and press the Use key (Default: E)

B.   Bind a key to the `sm_ping` command. For example:

```
bind mouse3 sm_ping
```

## Overrides

This plugin supports the use of [overrides](https://wiki.alliedmods.net/Overriding_Command_Access_(Sourcemod)) 

- `ping_custom_duration` - Allows players with this override to specify a custom duration argument for their ping, with the syntax `sm_ping <seconds>`
- `ping_cooldown_immunity` - Makes players immune to the cooldown system
