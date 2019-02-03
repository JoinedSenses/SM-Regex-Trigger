# TF2-Regex-Filter
**A plugin originally developed by Keith Warren [Sky Guardian], modified and maintained by myself.**  
**Serves as a filter for names, chat, and commands.**  
  
I have included the regex config file  which I use for my servers. It gets updated regularly.  
**FYI:** The "blank" section at the top of the config is intended. There is some weird bug occuring when it is removed, more than likely due to the funky characters used.  

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
	Notes: If using the discord api plugin, it requires you to create a config for name_filter and chat_filter  
	  I could also suggest modifying this plugin at line 136 if you wish to modify the server name that appears when relayed to discord.

## ConVars
```
sm_regex_status "1"  // Enable/Disable plugin  
sm_regex_config_path "configs/regexfilters/" // Don't touch. Config path of filters  
sm_regex_check_chat "1" // Enable chat checking  
sm_regex_check_commands "1" // Enable command checking  
sm_regex_check_names "1" // Enable name checking  
sm_regex_prefix "" // Prefix to add to randomly generated names if a players name is unnamed  
sm_regex_irc_enabled "0" // Enable use of IRC relay  
sm_regex_irc_main "" // Public server 'connect' messages are relayed to. Dont include the #  
```
## Installation  
 * Install regexfiltering.smx into your plugins folder.  
 * Either install the included config to addons/sourcemod/configs/regexfilters/  
  or create your own at that location.
 * Once the plugin has been loaded, it can be configured at cfg/sourcemod/plugin.regexfilters.txt  

**Discord formatting of filtered channel:**  
![alt text](https://i.imgur.com/WhD5wUh.png)
