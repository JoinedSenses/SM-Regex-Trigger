# TF2-Regex-Filter
A plugin created by Keith Warren [Sky Guardian], modified by myself. 
Serves as a filter for names, chat, and commands. 

See this plugin for reference, since they are similar: https://forums.alliedmods.net/showthread.php?t=71867

The uploaded source and plugin here would need to be edited for your own use:
  Specifically line 465 - I push the connect message to my IRC.
  There are also some additional irc relay messages, which I have formatted for discord.
  
  Filtered items are send to a hidden irc channel, which is then relayed to discord with a bot.

## Requirements

Hide Name Change plugin and Tidy Chat plugin
```
sm_tidychat_on 1 // 0/1 - On/off
sm_tidychat_connect 1 // 0/1 - Tidy connect messages

```
![alt text](https://i.imgur.com/kcn2GW2.png)
