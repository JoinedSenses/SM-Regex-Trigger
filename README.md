# TF2-Regex-Trigger
**Serves as a regex trigger/filter for names, chat, and commands.**  
  
I have included the regex config file which I use for my servers.  

If you are unfamilair with regex, check out  these websites:  
http://www.rexegg.com/regex-quickstart.html  
https://www.regular-expressions.info/  
https://regex101.com  

See this plugin for reference, since they are similar: https://forums.alliedmods.net/showthread.php?t=71867

*This plugin has included features which integrate the use of **SourceIRC** and **Discord** when connecting multiple servers.* 
https://github.com/Azelphur/SourceIRC (Original)  
https://github.com/JoinedSenses/SourceIRC (Modified)  
## Optional features:  
 * IRC: Method to relay 'connect' messages to a main IRC channel  
 * Discord: Method to relay filtered names and chat messages to a seperate channel for debugging/analysis.  
 * Notes: If using the discord api plugin, you're required to setup discord.cfg and to update /cfg/sourcemod/plugin.regextrigger.cfg  

## ConVars
```
sm_regex_allow "1" Status of the plugin.\n(1 = on, 0 = off)  
sm_regex_config_path "configs/regextriggers/" Location to store the regex filters at.  
sm_regex_check_chat "1" Filter out and check chat messages.  
sm_regex_check_commands "1" Filter out and check commands.  
sm_regex_check_names "1" Filter out and check names.  
sm_regex_prefix "" "Prefix for random name when player has become unnamed  
sm_regex_irc_enabled "0" Enable IRC relay for SourceIRC. Sends messages to flagged channels  
sm_regex_channelname "" Key name from discord.cfg for name relay  
sm_regex_channelchat "" Key name from discord.cfg for chat relay  
```
## Installation  
 * Install regexfiltering.smx into your plugins folder.  
 * Either install the included config to addons/sourcemod/configs/regexfilters/  
  or create your own at that location.
 * Once the plugin has been loaded, it can be configured at cfg/sourcemod/plugin.regexfilters.txt  

**Discord formatting of filtered channel:**  
![alt text](https://i.imgur.com/WhD5wUh.png)
  
  
## Config Keys
**Warn:** Display a warning message to the player  
`"warn" "msg"`  
Allows you to give fair warning about your rules when they are broken  

**Action:** Executed if a pattern matches  
`"action" "rcon action"`  
"rcon action" can be any command you want, but there may be only one action per section.  
%n, %i, and %u will be replaced with the clients name, index, or userid, respectively, if they are in the command string.  

**Block:** Block the text absolutely (**Does not work for names**)   
`"block" "1"`  
Very simple, skips all the replacement stuff, does not skip the limiting step, so you can block and limit at the same time (limit the amount of times one can attempt to say it, and also block the words from being said)  

**Limit:** Limit the amount of times the matched action can occur  
`"limit" "number"`  
Also simple, will block if the client says the pattern more times than "number"  

**Forgive:** Forgives one indiscretion every x seconds  
`"forgive" "x"`  
Allows more flexibility with limiting. It might be ok to advertise once every five minutes, not every five seconds, so you can "forgive" a slip up every "x" seconds.  

**Punish:** executes a punishment command if limit is exceeded  
`"punish" "cmd"`  
"cmd" can be any command you want, but there may be only one punishment per section.  
%n, %i, and %u will be replaced with the clients name, index, or userid, respectively, if they are in the command string.  

**Replace:** Replaces matched text with a value.  
`"replace" "with"`  
Will replace the pattern's matches with "with", and check everything again.  
Supports use of capture groups greater than 0 by using \#, such as \1 or \2  

**Relay:** Relays information to the related discord channel  
`"relay" "1"`  
If enabled and discord api is use, this will allow the plugin to relay messages to discord channels.  
