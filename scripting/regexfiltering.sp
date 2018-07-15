#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_DESCRIPTION "Regex filtering for names, chat and commands."
#define PLUGIN_VERSION "2.3.0"
#define MAX_EXPRESSION_LENGTH 256

#include <sourcemod>
#include <sdktools>
#include <regex>
#include <tf2>
#include <morecolors>

ConVar
	cvar_Status
	, cvar_ConfigPath
	, cvar_CheckChat
	, cvar_CheckCommands
	, cvar_CheckNames
	, cvar_UnnamedPrefix
	, cvar_IRC_Enabled
	, cvar_IRCMain
	, cvar_IRCFilteredMessages
	, cvar_IRCFilteredNames;
char
	sIRC_Main[32]
	, sIRC_FilteredMessages[32]
	, sIRC_FilteredNames[32];
bool
	g_bLate
	, g_bChanged[MAXPLAYERS+1]
	, checking[MAXPLAYERS+1];
char
	old_name[MAXPLAYERS+1][MAX_NAME_LENGTH]
	, original_name[MAXPLAYERS+1][MAX_NAME_LENGTH];
ArrayList
	g_hArray_Regex_Chat
	, g_hArray_Regex_Commands
	, g_hArray_Regex_Names;
StringMap
	g_hLimits[MAXPLAYERS+1];

public Plugin myinfo = {
	name = "Regex Filters", 
	author = "Keith Warren, JoinedSenses", 
	description = PLUGIN_DESCRIPTION, 
	version = PLUGIN_VERSION, 
	url = "https://github.com/JoinedSenses/TF2-Regex-Filter"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	g_bLate = late;
	return APLRes_Success;
}

public void OnPluginStart() {
	CreateConVar("sm_regexfilters_version", PLUGIN_VERSION, PLUGIN_DESCRIPTION, FCVAR_NOTIFY | FCVAR_DONTRECORD | FCVAR_SPONLY);
	cvar_Status = CreateConVar("sm_regex_status", "1", "Status of the plugin.\n(1 = on, 0 = off)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	cvar_ConfigPath = CreateConVar("sm_regex_config_path", "configs/regexfilters/", "Location to store the regex filters at.", FCVAR_NOTIFY);
	cvar_CheckChat = CreateConVar("sm_regex_check_chat", "1", "Filter out and check chat messages.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	cvar_CheckCommands = CreateConVar("sm_regex_check_commands", "1", "Filter out and check commands.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	cvar_CheckNames = CreateConVar("sm_regex_check_names", "1", "Filter out and check names.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	cvar_UnnamedPrefix = CreateConVar("sm_regex_prefix", "", "Prefix for random name when player has become unnamed");
	cvar_IRC_Enabled = CreateConVar("sm_regex_irc_enabled", "0", "Enable IRC relay from SourceIRC", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	cvar_IRCMain =  CreateConVar("sm_regex_irc_main", "", "Main channel for connect message relay", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	cvar_IRCFilteredMessages =  CreateConVar("sm_regex_irc_messages", "", "Channel for filtered messages", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	cvar_IRCFilteredNames =  CreateConVar("sm_regex_irc_names", "", "Channel for filtered names", FCVAR_NOTIFY, true, 0.0, true, 1.0);

	HookUserMessage(GetUserMessageId("SayText2"), UserMessageHook, true);
	
	g_hArray_Regex_Chat = new ArrayList(2);
	g_hArray_Regex_Commands = new ArrayList(2);
	g_hArray_Regex_Names = new ArrayList(2);
	
	HookEvent("player_connect_client", Event_PlayerConnect, EventHookMode_Pre);
	HookEvent("player_changename", Event_OnChangeName, EventHookMode_Pre);
	//RegAdminCmd("sm_testname", Command_TestName, ADMFLAG_ROOT);
	
	AutoExecConfig();
}

//public Action Command_TestName(int client, int args)
//{
//	char sName[MAX_NAME_LENGTH];
//	GetCmdArgString(sName, sizeof(sName));
//	
//	Action value = CheckClientName(client, null, sName);
//	PrintToChat(client, "action value: %i", value);
//	return Plugin_Handled;
//}

public void OnConfigsExecuted() {
	if (!cvar_Status.BoolValue) {
		return;
	}
	
	cvar_IRCMain.GetString(sIRC_Main, sizeof(sIRC_Main));
	cvar_IRCFilteredMessages.GetString(sIRC_FilteredMessages, sizeof(sIRC_FilteredMessages));
	cvar_IRCFilteredNames.GetString(sIRC_FilteredNames, sizeof(sIRC_FilteredNames));
	
	char
		sConfigPath[PLATFORM_MAX_PATH]
		, sPath[PLATFORM_MAX_PATH]
		, sBaseConfig[PLATFORM_MAX_PATH];
		
	cvar_ConfigPath.GetString(sConfigPath, sizeof(sConfigPath));
	BuildPath(Path_SM, sPath, sizeof(sPath), sConfigPath);
	FormatEx(sBaseConfig, sizeof(sBaseConfig), "%sregexfilters.cfg", sPath);
	LoadExpressions(sBaseConfig);
	
	// char sMap[64];
	// GetCurrentMap(sMap, sizeof(sMap));
	
	// char sMapConfig[PLATFORM_MAX_PATH];
	// FormatEx(sBaseConfig, sizeof(sBaseConfig), "%s/maps/regexfilters_%s.cfg", sPath, sMap);
	// LoadExpressions(sMapConfig);
	
	CreateTimer(2.0, Timer_DelayLate, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_DelayLate(Handle timer) {
	if (g_bLate) {
		if (g_hLimits[0] == null) {
			g_hLimits[0] = new StringMap();
		}
		g_bLate = false;
	}
}

public void OnMapStart() {
	g_hLimits[0] = new StringMap();
}

public void OnMapEnd() {
	delete g_hLimits[0];
}
public Action Event_PlayerConnect(Event event, const char[] name, bool dontBroadcast) {
	event.BroadcastDisabled = true;
	return Plugin_Continue;
}
public Action UserMessageHook(UserMsg msg_hd, BfRead bf, const int[] players, int playersNum, bool reliable, bool init) {
	char sMessage[96];
	bf.ReadString(sMessage, sizeof(sMessage));
	bf.ReadString(sMessage, sizeof(sMessage));
	if (StrContains(sMessage, "Name_Change") != -1) {
		return Plugin_Handled;
	}
	return Plugin_Continue;
}
public void OnClientAuthorized(int client, const char[] auth) {
	if (!cvar_Status.BoolValue) {
		return;
	}
	g_hLimits[client] = new StringMap();
	if (cvar_CheckNames.BoolValue){
		char sName[MAX_NAME_LENGTH];
		GetClientName(client, sName, sizeof(sName));
		strcopy(original_name[client], MAX_NAME_LENGTH, sName);
		
		CheckClientName(client, sName);
	}
	GetClientName(client, old_name[client], MAX_NAME_LENGTH);
	PrintToChatAll("%s connected", old_name[client]);

	if (g_bChanged[client]) {
		if (cvar_IRC_Enabled.BoolValue) {
			ServerCommand("irc_send PRIVMSG #%s :`%s`  -->  `%s`", sIRC_FilteredNames, original_name[client], old_name[client]);
		}
		g_bChanged[client] = false;
	}
}

public void OnClientDisconnect(int client) {
	delete g_hLimits[client];
	g_bChanged[client] = false;
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs) {
	if (!cvar_Status.BoolValue || !cvar_CheckChat.BoolValue) {
		return Plugin_Continue;
	}
	
	char sMessage[255];
	strcopy(sMessage, sizeof(sMessage), sArgs);
	
	if (strlen(sMessage) == 0) {
		return Plugin_Continue;
	}
	
	int begin;
	int end = g_hArray_Regex_Chat.Length;
	RegexError errorcode = REGEX_ERROR_NONE;
	bool changed;
	Handle save[2];
	Regex regex;
	StringMap currentsection;
	any value;
	char sValue[256];
	
	while (begin != end) {
		g_hArray_Regex_Chat.GetArray(begin, save, sizeof(save));
		regex = view_as<Regex>(save[0]);
		currentsection = view_as<StringMap>(save[1]);
		value = regex.Match(sMessage, errorcode);
		
		if (value > 0 && errorcode == REGEX_ERROR_NONE) {
			if (currentsection.GetValue("immunity", value) && CheckCommandAccess(client, "", value, true)) {
				return Plugin_Continue;
			}
			if (currentsection.GetString("warn", sValue, sizeof(sValue))) {
				CPrintToChat(client, "[{red}Filter{default}] {lightgreen}%s{default}", sValue);
			}
			if (currentsection.GetString("action", sValue, sizeof(sValue))) {
				ParseAndExecute(client, sValue, sizeof(sValue));
			}
			if (currentsection.GetValue("limit", value)) {
				FormatEx(sValue, sizeof(sValue), "%i", regex);
				
				any at;
				g_hLimits[client].GetValue(sValue, at);
				
				int mod;
				if (currentsection.GetValue("forgive", mod)) {
					FormatEx(sValue, sizeof(sValue), "%i-limit", regex);
					
					float date;
					if (!g_hLimits[client].GetValue(sValue, date)) {
						date = GetGameTime();
						g_hLimits[client].SetValue(sValue, date);
					}
					
					date = GetGameTime() - date;
					at = at - (RoundToCeil(date) & mod);
				}
				
				g_hLimits[client].SetValue(sValue, at);
				
				if (at > value) {
					if (currentsection.GetString("punish", sValue, sizeof(sValue))) {
						ParseAndExecute(client, sValue, sizeof(sValue));
					}
					return Plugin_Handled;
				}
			}
			
			if (currentsection.GetValue("block", value) && view_as<bool>(value)) {
				char sName[MAX_NAME_LENGTH];
				GetClientName(client, sName, MAX_NAME_LENGTH);
				if (StrContains(sName, "`") != -1) {
					ReplaceString(sName, sizeof(sName), "`", "´");				
				}
				if (StrContains(sMessage, "`") != -1) {
					ReplaceString(sMessage, sizeof(sMessage), "`", "´");			
				}
				if (StrContains(sMessage, ";") != -1) {
					ReplaceString(sMessage, sizeof(sMessage), ";", ":");
				}
				if (cvar_IRC_Enabled.BoolValue) {
					ServerCommand("irc_send PRIVMSG #%s :%s: `%s`", sIRC_FilteredMessages, sName, sMessage);
				}
				return Plugin_Handled;
			}
			
			if (currentsection.GetValue("replace", value)) {
				int random = GetRandomInt(0, view_as<ArrayList>(value).Length - 1);
				
				DataPack pack = view_as<DataPack>(view_as<ArrayList>(value).Get(random));
				pack.Reset();

				Regex regex2 = pack.ReadCell();
				pack.ReadString(sValue, sizeof(sValue));
				
				if (regex2 == null) {
					regex2 = regex;
				}
				
				random = regex2.Match(sMessage, errorcode);
				
				if (random > 0 && errorcode == REGEX_ERROR_NONE) {
					changed = true;
					char[][] sArray = new char[random][256];
					
					for (int a = 0; a < random; a++) {
						regex2.GetSubString(a, sArray[a], sizeof(sValue));
					}
					
					for (int a = 0; a < random; a++) {
						ReplaceString(sMessage, sizeof(sMessage), sArray[a], sValue);
					}
					
					begin = 0;
				}
			}
		}
		
		begin++;
	}
	
	if (changed) {
		if (client == 0) {
			ServerCommand("say %s", sMessage);
		}
		else {
			FakeClientCommand(client, "%s %s", command, sMessage);
			return Plugin_Handled;
		}
	}
	
	return Plugin_Continue;
}

public Action Event_OnChangeName(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!cvar_Status.BoolValue || !cvar_CheckNames.BoolValue) {
		return Plugin_Handled;
	}
	char sNewName[MAX_NAME_LENGTH];
	event.GetString("newname", sNewName, sizeof(sNewName));
	
	if (!g_bChanged[client]) {
		strcopy(original_name[client],MAX_NAME_LENGTH, sNewName);
		checking[client] = false;
	}
	if (!checking[client]) {
		CheckClientName(client, sNewName);
	}
	return Plugin_Handled;
}
Action CheckClientName(int client, char[] new_name) {
	checking[client] = true;
	int begin;
	int end = g_hArray_Regex_Names.Length;
	RegexError errorcode = REGEX_ERROR_NONE;
	bool changed;
	Handle save[2];
	Regex regex;
	StringMap currentsection;
	any value;
	char sValue[256];

	while (begin != end) {
		g_hArray_Regex_Names.GetArray(begin, save, sizeof(save));
		regex = view_as<Regex>(save[0]);
		currentsection = view_as<StringMap>(save[1]);
		if (StrEqual(new_name, "")) {
			break;
		}
		value = regex.Match(new_name, errorcode);

		if (value > 0 && errorcode == REGEX_ERROR_NONE) {
			if (currentsection.GetValue("immunity", value) && CheckCommandAccess(client, "", value, true)) {
				return Plugin_Continue;
			}
			if (currentsection.GetString("warn", sValue, sizeof(sValue))) {
				CPrintToChat(client, "[{red}Filter{default}] {lightgreen}%s{default}", sValue);
			}
			if (currentsection.GetString("action", sValue, sizeof(sValue))) {
				ParseAndExecute(client, sValue, sizeof(sValue));
			}
			if (currentsection.GetValue("limit", value)) {
				FormatEx(sValue, sizeof(sValue), "%i", regex);
				
				any at;
				g_hLimits[client].GetValue(sValue, at);
				
				int mod;
				if (currentsection.GetValue("forgive", mod)) {
					FormatEx(sValue, sizeof(sValue), "%i-limit", regex);
					
					float date;
					if (!g_hLimits[client].GetValue(sValue, date)) {
						date = GetGameTime();
						g_hLimits[client].SetValue(sValue, date);
					}
					
					date = GetGameTime() - date;
					at = at - (RoundToCeil(date) & mod);
				}
				
				g_hLimits[client].SetValue(sValue, at);
				
				if (at > value) {
					if (currentsection.GetString("punish", sValue, sizeof(sValue))) {
						ParseAndExecute(client, sValue, sizeof(sValue));
					}
					
					return Plugin_Handled;
				}
			}
			if (currentsection.GetValue("block", value) && view_as<bool>(value)) {
				return Plugin_Handled;
			}
			if (currentsection.GetValue("replace", value)) {
				int random = GetRandomInt(0, view_as<ArrayList>(value).Length - 1);
				
				DataPack pack = view_as<DataPack>(view_as<ArrayList>(value).Get(random));
				pack.Reset();

				Regex regex2 = ReadPackCell(pack);
				pack.ReadString(sValue, sizeof(sValue));

				if (regex2 == null) {
					regex2 = regex;
				}
				
				random = regex2.Match(new_name, errorcode);
				
				if (random > 0 && errorcode == REGEX_ERROR_NONE) {
					g_bChanged[client] = true;
					changed = true;
					char[][] sArray = new char[random][256];
					
					for (int a = 0; a < random; a++) {
						regex2.GetSubString(a, sArray[a], sizeof(sValue));
					}
					for (int a = 0; a < random; a++) {
						if (StrEqual(sValue, "remove", false)) {
							ReplaceString(new_name, MAX_NAME_LENGTH, sArray[a], "");
						}
						else {
							ReplaceString(new_name, MAX_NAME_LENGTH, sArray[a], sValue);
						}
					}	
					begin = 0;
				}
			}
		}
		begin++;
	}

	if (changed) {
		// TerminateNameUTF8(new_name);
		if (strlen(new_name)==0) {
			char sPrefix[MAX_NAME_LENGTH];
			char RandomNameArray[][] = {
				"Steve","John","James", "Robert","David","Mike","Daniel","Kevin","Ryan","Gary",
				"Larry","Frank","Jerry","Greg","Doug","Carl","Gerald","Billy","Bobby","Brooke","Bort"
				};
			int randomnum = GetRandomInt(0, sizeof(RandomNameArray[]) - 1);
			cvar_UnnamedPrefix.GetString(sPrefix, sizeof(sPrefix));
			FormatEx(new_name, MAX_NAME_LENGTH, "%s%s", sPrefix, RandomNameArray[randomnum]);
		}
		if (IsClientConnected(client)) {
			SetClientName(client, new_name);
			if (StrContains(original_name[client], "`") != -1) {
				ReplaceString(original_name[client], MAX_NAME_LENGTH, "`", "´");
			}
			if (StrContains(original_name[client], ";") != -1) {
				ReplaceString(original_name[client], MAX_NAME_LENGTH, ";", ":");
			}
			if (StrContains(new_name, "`") != -1) {
				ReplaceString(new_name, MAX_NAME_LENGTH, "`", "´");
			}
			checking[client] = false;
			changed = false;
			return Plugin_Handled;
		}
	}
	else {
		if (g_bChanged[client]) {
			if (cvar_IRC_Enabled.BoolValue) {
				ServerCommand("irc_send PRIVMSG #%s :`%s`  -->  `%s`", sIRC_FilteredNames, original_name[client], new_name);
			}
			g_bChanged[client] = false;
		}
		if (IsClientInGame(client)) {
			if (StrEqual(old_name[client], new_name)) {
				return Plugin_Continue;
			}
			if (cvar_IRC_Enabled.BoolValue) {
				ServerCommand("irc_send PRIVMSG #%s :%s changed name to %s", sIRC_Main, old_name[client], new_name);
			}
			if (view_as<TFTeam>(GetClientTeam(client)) == TFTeam_Red) {
				CPrintToChatAll("* {red}%s{default} changed name to {red}%s{default}", old_name[client], new_name);
			}
			else if (view_as<TFTeam>(GetClientTeam(client)) == TFTeam_Blue) {
				CPrintToChatAll("* {blue}%s{default} changed name to {blue}%s{default}", old_name[client], new_name);
			}
			else if (view_as<TFTeam>(GetClientTeam(client)) == TFTeam_Spectator) {
				CPrintToChatAll("* %s changed name to %s", old_name[client], new_name);
			}
		}
	}
	strcopy(old_name[client], MAX_NAME_LENGTH, new_name);
	return Plugin_Continue;
}

// ensures that utf8 names are properly terminated
// void TerminateNameUTF8(char[] name) { 
	// int len = strlen(name); 
	
	// for (int i = 0; i < len; i++) {
		// int bytes = IsCharMB(name[i]);
		// if (bytes > 1) {
			// if (len - i < bytes) {
				// name[i] = '\0';
				// return;
			// }
			// i += bytes - 1;
		// }
	// }
// }

public Action OnClientCommand(int client, int args) {
	if (!cvar_Status.BoolValue || !cvar_CheckCommands.BoolValue)
		return Plugin_Continue;
	
	char sCommand[255];
	GetCmdArg(0, sCommand, sizeof(sCommand));
	
	if (strlen(sCommand) == 0) {
		return Plugin_Continue;
	}
	
	int begin;
	int end = g_hArray_Regex_Commands.Length;
	RegexError errorcode = REGEX_ERROR_NONE;
	bool changed;
	Handle save[2];
	Regex regex;
	StringMap currentsection;
	any value;
	char sValue[256];
	
	while (begin != end) {
		g_hArray_Regex_Commands.GetArray(begin, save, sizeof(save));
		regex = view_as<Regex>(save[0]);
		currentsection = view_as<StringMap>(save[1]);
		value = regex.Match(sCommand, errorcode);
		
		if (value > 0 && errorcode == REGEX_ERROR_NONE) {
			if (currentsection.GetValue("immunity", value) && CheckCommandAccess(client, "", value, true)) {
				return Plugin_Continue;
			}
			if (currentsection.GetString("warn", sValue, sizeof(sValue))) {
				ReplyToCommand(client, "[Filter] %s", sValue);
			}
			if (currentsection.GetString("action", sValue, sizeof(sValue))) {
				ParseAndExecute(client, sValue, sizeof(sValue));
			}
			if (currentsection.GetValue("limit", value)) {
				FormatEx(sValue, sizeof(sValue), "%i", regex);
				
				any at;
				g_hLimits[client].GetValue(sValue, at);
				
				int mod;
				if (currentsection.GetValue("forgive", mod)) {
					FormatEx(sValue, sizeof(sValue), "%i-limit", regex);
					
					float date;
					if (!g_hLimits[client].GetValue(sValue, date)) {
						date = GetGameTime();
						g_hLimits[client].SetValue(sValue, date);
					}
					
					date = GetGameTime() - date;
					at = at - (RoundToCeil(date) & mod);
				}

				g_hLimits[client].SetValue(sValue, at);

				if (at > value) {
					if (currentsection.GetString("punish", sValue, sizeof(sValue))) {
						ParseAndExecute(client, sValue, sizeof(sValue));
					}
					return Plugin_Handled;
				}
			}
			
			if (currentsection.GetValue("block", value) && view_as<bool>(value)) {
				return Plugin_Handled;
			}
			if (currentsection.GetValue("replace", value)) {
				int random = GetRandomInt(0, view_as<ArrayList>(value).Length - 1);
				
				DataPack pack = view_as<DataPack>(view_as<ArrayList>(value).Get(random));
				pack.Reset();
				
				Regex regex2 = ReadPackCell(pack);
				pack.ReadString(sValue, sizeof(sValue));
				
				if (regex2 == null) {
					regex2 = regex;
				}

				random = regex2.Match(sCommand, errorcode);
				
				if (random > 0 && errorcode == REGEX_ERROR_NONE) {
					changed = true;
					char[][] sArray = new char[random][256];
					
					for (int a = 0; a < random; a++) {
						regex2.GetSubString(a, sArray[a], sizeof(sValue));
					}
					
					for (int a = 0; a < random; a++) {
						ReplaceString(sCommand, sizeof(sCommand), sArray[a], sValue);
					}
					
					begin = 0;
				}
			}
		}
		begin++;
	}
	
	if (changed) {
		if (client == 0) {
			ServerCommand("%s", sCommand);
		}
		else {
			FakeClientCommand(client, "%s", sCommand);
			return Plugin_Handled;
		}
	}
	
	return Plugin_Continue;
}

void ParseAndExecute(int client, char[] command, int size) {
	char sReplace[256];
	
	if (client == 0) {
		FormatEx(sReplace, sizeof(sReplace), "0");
	}
	else {
		FormatEx(sReplace, sizeof(sReplace), "%i", GetClientUserId(client));
	}
	
	ReplaceString(command, size, "%u", sReplace);
	
	if (client != 0) {
		FormatEx(sReplace, sizeof(sReplace), "%i", client);
	}
	
	ReplaceString(command, size, "%i", sReplace);
	GetClientName(client, sReplace, MAX_NAME_LENGTH);
	ReplaceString(command, size, "%n", sReplace);
	ServerCommand(command);
}

void LoadExpressions(const char[] file) {
	KeyValues kv = new KeyValues("RegexFilters");
	
	if (FileExists(file)) {
		kv.ImportFromFile(file);
		// KeyValuesToFile(kv, file);
	}
	
	if (KvGotoFirstSubKey(kv)) {
		do{
			char sName[128];
			kv.GetSectionName(sName, sizeof(sName));
			
			StringMap currentsection = new  StringMap();
			currentsection.SetString("name", sName);
			
			ParseSectionValues(kv, currentsection);
		}
		while (kv.GotoNextKey());
	}
	
	delete kv;
}

void ParseSectionValues(KeyValues kv, StringMap currentsection) {
	if (!kv.GotoFirstSubKey(false)) {
		return;
	}
	
	do {
		char sKey[128];
		kv.GetSectionName(sKey, sizeof(sKey));
		
		char sValue[128];
		
		if (StrEqual(sKey, "chatpattern")) {
			kv.GetString(NULL_STRING, sValue, sizeof(sValue));
			RegisterExpression(sValue, currentsection, g_hArray_Regex_Chat);
		}
		else if (StrEqual(sKey, "cmdpattern") || StrEqual(sKey, "commandkeyword")) {
			kv.GetString(NULL_STRING, sValue, sizeof(sValue));
			RegisterExpression(sValue, currentsection, g_hArray_Regex_Commands);
		}
		else if (StrEqual(sKey, "namepattern")) {
			kv.GetString(NULL_STRING, sValue, sizeof(sValue));
			RegisterExpression(sValue, currentsection, g_hArray_Regex_Names);
		}
		else if (StrEqual(sKey, "replace")) {
			any value;
			if (!currentsection.GetValue("replace", value)) {
				value = new ArrayList();
				currentsection.SetValue("replace", value);
			}
			
			kv.GetString(NULL_STRING, sValue, sizeof(sValue));
			AddReplacement(sValue, value);
		}
		else if (StrEqual(sKey, "replacepattern")) {
			any value;
			if (!currentsection.GetValue("replace", value)) {
				value = new ArrayList();
				currentsection.SetValue("replace", value);
			}
			
			kv.GetString(NULL_STRING, sValue, sizeof(sValue));
			AddPatternReplacement(sValue, value);
		}
		else if (StrEqual(sKey, "block")) {
			currentsection.SetValue(sKey, KvGetNum(kv, NULL_STRING));
		}
		else if (StrEqual(sKey, "action")) {
			kv.GetString(NULL_STRING, sValue, sizeof(sValue));
			currentsection.SetString(sKey, sValue);}
		else if (StrEqual(sKey, "warn")) {
			kv.GetString(NULL_STRING, sValue, sizeof(sValue));
			currentsection.SetString(sKey, sValue);
		}
		else if (StrEqual(sKey, "limit"))
			currentsection.SetValue(sKey, KvGetNum(kv, NULL_STRING));
		else if (StrEqual(sKey, "forgive"))
			currentsection.SetValue(sKey, KvGetNum(kv, NULL_STRING));
		else if (StrEqual(sKey, "punish")) {
			kv.GetString(NULL_STRING, sValue, sizeof(sValue));
			currentsection.SetString(sKey, sValue);
		}
		else if (StrEqual(sKey, "immunity")) {
			kv.GetString(NULL_STRING, sValue, sizeof(sValue));
			currentsection.SetValue(sKey, ReadFlagString(sValue));
		}
	}
	while (kv.GotoNextKey(false));
	
	kv.GoBack();
}

void RegisterExpression(const char[] key, StringMap currentsection, ArrayList data) {
	char sExpression[MAX_EXPRESSION_LENGTH];
	int flags = ParseExpression(key, sExpression, sizeof(sExpression));
	
	if (flags == -1) {
		return;
	}
	
	char sError[128];
	RegexError errorcode;
	Regex regex = new Regex(sExpression, flags, sError, sizeof(sError), errorcode);
	
	if (regex == null) {
		LogError("Error compiling expression '%s' with flags '%i': [%i] %s", sExpression, flags, errorcode, sError);
		return;
	}
	
	Handle save[2];
	save[0] = view_as<Handle>(regex);
	save[1] = view_as<Handle>(currentsection);
	
	data.PushArray(save, sizeof(save));
}

int ParseExpression(const char[] key, char[] expression, int size) {
	strcopy(expression, size, key);
	TrimString(expression);
	
	int
		flags
		, a
		, b
		, c;
	
	if (expression[strlen(expression) - 1] == '\'') {
		for (; expression[flags] != '\0'; flags++) {
			if (expression[flags] == '\'') {
				a++;
				b = c;
				c = flags;
			}
		}
		
		if (a < 2) {
			LogError("Regex Filter line malformed: %s", key);
			return -1;
		}
		else {
			expression[b] = '\0';
			expression[c] = '\0';
			flags = FindRegexFlags(expression[b + 1]);
			
			TrimString(expression);
			
			if (a > 2 && expression[0] == '\'') {
				strcopy(expression, strlen(expression) - 1, expression[1]);
			}
		}
	}
	
	return flags;
}

int FindRegexFlags(const char[] flags) {
	char sBuffer[7][16];
	ExplodeString(flags, "|", sBuffer, 7, 16);
	
	int new_flags;
	for (int i = 0; i < 7; i++) {
		if (sBuffer[i][0] == '\0') {
			continue;
		}
		if (StrEqual(sBuffer[i], "CASELESS")) {
			new_flags |= PCRE_CASELESS;
		}
		else if (StrEqual(sBuffer[i], "MULTILINE")) {
			new_flags |= PCRE_MULTILINE;
		}
		else if (StrEqual(sBuffer[i], "DOTALL")) {
			new_flags |= PCRE_DOTALL;
		}
		else if (StrEqual(sBuffer[i], "EXTENDED")) {
			new_flags |= PCRE_EXTENDED;
		}
		else if (StrEqual(sBuffer[i], "UNGREEDY")) {
			new_flags |= PCRE_UNGREEDY;
		}
		else if (StrEqual(sBuffer[i], "UTF8")) {
			new_flags |= PCRE_UTF8;
		}
		else if (StrEqual(sBuffer[i], "NO_UTF8_CHECK")) {
			new_flags |= PCRE_NO_UTF8_CHECK;
		}
	}
	
	return new_flags;
}

void AddReplacement(const char[] value, ArrayList data) {
	DataPack pack = new DataPack();
	pack.WriteCell(view_as<Handle>(null));
	pack.WriteString(value);
	data.Push(pack);
}

void AddPatternReplacement(const char[] value, ArrayList data) {
	char sExpression[MAX_EXPRESSION_LENGTH];
	int flags = ParseExpression(value, sExpression, sizeof(sExpression));
	
	if (flags == -1) {
		return;
	}
	
	char sError[128];
	RegexError errorcode;
	Regex regex = new Regex(sExpression, flags, sError, sizeof(sError), errorcode);
	
	if (regex == null) {
		LogError("Error compiling expression '%s' with flags '%i': [%i] %s", sExpression, flags, errorcode, sError);
		return;
	}
	
	DataPack pack = new DataPack();
	pack.WriteCell(regex);
	pack.WriteString("");
	data.Push(pack);
}