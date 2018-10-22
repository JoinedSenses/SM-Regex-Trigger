#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_DESCRIPTION "Regex filtering for names, chat and commands."
#define PLUGIN_VERSION "2.4.2"
#define MAX_EXPRESSION_LENGTH 256

#include <sourcemod>
#include <sdktools>
#include <regex>
#include <tf2>
#include <morecolors>

ConVar
	  g_cvarStatus
	, g_cvarConfigPath
	, g_cvarCheckChat
	, g_cvarCheckCommands
	, g_cvarCheckNames
	, g_cvarUnnamedPrefix
	, g_cvarIRC_Enabled
	, g_cvarIRCMain
	, g_cvarIRCFilteredMessages
	, g_cvarIRCFilteredNames;
char
	  g_sIRC_Main[32]
	, g_sIRC_FilteredMessages[32]
	, g_sIRC_FilteredNames[32]
	, g_sOldName[MAXPLAYERS+1][MAX_NAME_LENGTH]
	, g_sUnfilteredName[MAXPLAYERS+1][MAX_NAME_LENGTH]
	, g_sPrefix[MAX_NAME_LENGTH];
bool
	  g_bLate
	, g_bChanged[MAXPLAYERS+1]
	, g_bChecking[MAXPLAYERS+1]
	, g_bChecked[MAXPLAYERS+1];
ArrayList
	  g_hArray_Regex_Chat
	, g_hArray_Regex_Commands
	, g_hArray_Regex_Names;
StringMap
	  g_hLimits[MAXPLAYERS+1];

char g_sRandomNames[][] = {
	  "Steve"
	, "John"
	, "James"
	, "Robert"
	, "David"
	, "Mike"
	, "Daniel"
	, "Kevin"
	, "Ryan"
	, "Gary"
	, "Larry"
	, "Frank"
	, "Jerry"
	, "Greg"
	, "Doug"
	, "Carl"
	, "Gerald"
	, "Goose"
	, "Billy"
	, "Bobby"
	, "Brooke"
	, "Bort"
};

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
	g_cvarStatus = CreateConVar("sm_regex_status", "1", "Status of the plugin.\n(1 = on, 0 = off)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvarConfigPath = CreateConVar("sm_regex_config_path", "configs/regexfilters/", "Location to store the regex filters at.", FCVAR_NOTIFY);
	g_cvarCheckChat = CreateConVar("sm_regex_check_chat", "1", "Filter out and check chat messages.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvarCheckCommands = CreateConVar("sm_regex_check_commands", "1", "Filter out and check commands.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvarCheckNames = CreateConVar("sm_regex_check_names", "1", "Filter out and check names.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvarUnnamedPrefix = CreateConVar("sm_regex_prefix", "", "Prefix for random name when player has become unnamed");
	g_cvarIRC_Enabled = CreateConVar("sm_regex_irc_enabled", "0", "Enable IRC relay from SourceIRC", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvarIRCMain = CreateConVar("sm_regex_irc_main", "", "Main channel for connect message relay", FCVAR_NOTIFY);
	g_cvarIRCFilteredMessages = CreateConVar("sm_regex_irc_messages", "", "Channel for filtered messages", FCVAR_NOTIFY);
	g_cvarIRCFilteredNames = CreateConVar("sm_regex_irc_names", "", "Channel for filtered names", FCVAR_NOTIFY);

	HookUserMessage(GetUserMessageId("SayText2"), UserMessageHook, true);

	
	g_hArray_Regex_Chat = new ArrayList(3);
	g_hArray_Regex_Commands = new ArrayList(3);
	g_hArray_Regex_Names = new ArrayList(3);
	
	HookEvent("player_connect_client", Event_PlayerConnect, EventHookMode_Pre);
	HookEvent("player_changename", Event_OnChangeName, EventHookMode_Pre);
	RegAdminCmd("sm_testname", cmdTestName, ADMFLAG_ROOT);
	RegAdminCmd("sm_recheckname", cmdRecheckName, ADMFLAG_ROOT);
	
	AutoExecConfig();

	g_cvarUnnamedPrefix.AddChangeHook(convarChanged);

	CreateTimer(5.0, TimerLoadExpressions);

	if (g_bLate) {
		if (g_hLimits[0] == null) {
			g_hLimits[0] = new StringMap();
		}
		g_bLate = false;

		for (int i = 1; i <= MaxClients; i++) {
			if (isValidClient(i)) {
				Format(g_sOldName[i], sizeof(g_sOldName[]), "%N", i);
			}
		}
	}
	g_cvarUnnamedPrefix.GetString(g_sPrefix, sizeof(g_sPrefix));
}

bool isValidClient(int client) {
	return (0 < client <= MaxClients && IsClientConnected(client) && !IsFakeClient(client));
}

void convarChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	g_cvarUnnamedPrefix.GetString(g_sPrefix, sizeof(g_sPrefix));
}

public Action cmdTestName(int client, int args) {
	char arg[MAX_MESSAGE_LENGTH];
	GetCmdArgString(arg, sizeof(arg));

	Action value = CheckClientName(client, arg);
	ReplyToCommand(client, "action value: %i", value);
	return Plugin_Handled;
}

public Action cmdRecheckName(int client, int args) {
	char targetName[MAX_NAME_LENGTH];
	GetCmdArg(1, targetName, sizeof(targetName));
	int target = FindTarget(client, targetName);
	if (!target) {
		ReplyToCommand(client, "[Filter] Unable to find target");
		return Plugin_Handled;
	}
	ConnectNameCheck(target);
	ReplyToCommand(client, "[Filter] Name Check successful");
	return Plugin_Handled;
}

public Action TimerLoadExpressions(Handle timer) {
	if (!g_cvarStatus.BoolValue) {
		return;
	}
	
	g_cvarIRCMain.GetString(g_sIRC_Main, sizeof(g_sIRC_Main));
	g_cvarIRCFilteredMessages.GetString(g_sIRC_FilteredMessages, sizeof(g_sIRC_FilteredMessages));
	g_cvarIRCFilteredNames.GetString(g_sIRC_FilteredNames, sizeof(g_sIRC_FilteredNames));
	
	char sConfigPath[PLATFORM_MAX_PATH];
	char sPath[PLATFORM_MAX_PATH];
	char sBaseConfig[PLATFORM_MAX_PATH];
		
	g_cvarConfigPath.GetString(sConfigPath, sizeof(sConfigPath));
	BuildPath(Path_SM, sPath, sizeof(sPath), sConfigPath);
	FormatEx(sBaseConfig, sizeof(sBaseConfig), "%sregexfilters.cfg", sPath);
	LoadExpressions(sBaseConfig);
}

public void OnMapStart() {
	g_hLimits[0] = new StringMap();
}

public void OnMapEnd() {
	delete g_hLimits[0];
	for (int i = 1; i <= MaxClients; i++) {
		g_sOldName[i] = "";
	}
}

public void OnClientAuthorized(int client) {
	if (!g_cvarStatus.BoolValue) {
		return;
	}
	ConnectNameCheck(client);
}

public void OnClientPutInServer(int client) {
	if (!g_bChecking[client] && !g_bChecked[client]) {
		ConnectNameCheck(client);
	}
}

void ConnectNameCheck(int client) {
	g_hLimits[client] = new StringMap();
	if (g_cvarCheckNames.BoolValue){
		char sName[MAX_NAME_LENGTH];
		GetClientName(client, sName, sizeof(sName));
		strcopy(g_sUnfilteredName[client], MAX_NAME_LENGTH, sName);
		
		CheckClientName(client, sName);
	}
}

public void OnClientDisconnect(int client) {
	delete g_hLimits[client];
	g_bChanged[client] = false;
	g_bChecked[client] = false;
	g_bChecking[client] = false;
	g_sOldName[client] = "";
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs) {
	if (!g_cvarStatus.BoolValue || !g_cvarCheckChat.BoolValue) {
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
				if (g_cvarIRC_Enabled.BoolValue) {
					ServerCommand("irc_send PRIVMSG #%s :%s: `%s`", g_sIRC_FilteredMessages, sName, sMessage);
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
	if (!g_cvarStatus.BoolValue || !g_cvarCheckNames.BoolValue) {
		return Plugin_Continue;
	}

	int client = GetClientOfUserId(event.GetInt("userid"));
	char sNewName[MAX_NAME_LENGTH];
	event.GetString("newname", sNewName, sizeof(sNewName));
	
	if (StrEqual(g_sOldName[client], sNewName)) {
		return Plugin_Handled;
	}

	if (!g_bChanged[client]) {
		strcopy(g_sUnfilteredName[client], MAX_NAME_LENGTH, sNewName);
		g_bChecking[client] = false;
	}
	if (!g_bChecking[client]) {
		CheckClientName(client, sNewName);
	}

	return Plugin_Handled;
}

Action CheckClientName(int client, char[] new_name) {
	g_bChecking[client] = true;
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
						bool remove = (StrEqual(sValue, "remove", false));
						ReplaceString(new_name, MAX_NAME_LENGTH, sArray[a], remove ? "" : sValue);
					}	
					begin = 0;
				}
			}
		}
		begin++;
	}
	TerminateNameUTF8(new_name);
	if (StrEqual(g_sOldName[client], new_name)) {
		g_bChecking[client] = false;
		return Plugin_Handled;
	}
	if (changed) {
		if (strlen(new_name)==0) {
			int randomnum = GetRandomInt(0, sizeof(g_sRandomNames)-1);
			FormatEx(new_name, MAX_NAME_LENGTH, "%s%s", g_sPrefix, g_sRandomNames[randomnum]);
		}
		if (IsClientConnected(client)) {

			if (StrContains(g_sUnfilteredName[client], "`") != -1) {
				ReplaceString(g_sUnfilteredName[client], MAX_NAME_LENGTH, "`", "´");
			}
			if (StrContains(g_sUnfilteredName[client], ";") != -1) {
				ReplaceString(g_sUnfilteredName[client], MAX_NAME_LENGTH, ";", ":");
			}
			if (StrContains(new_name, "`") != -1) {
				ReplaceString(new_name, MAX_NAME_LENGTH, "`", "´");
			}
			if (g_cvarIRC_Enabled.BoolValue) {
				ServerCommand("irc_send PRIVMSG #%s :`%s`  -->  `%s`", g_sIRC_FilteredNames, g_sUnfilteredName[client], new_name);
			}
			changed = false;
			g_bChanged[client] = false;
		}
	}

	SetClientInfo(client, "name", new_name);

	if (IsClientInGame(client)) {
		if (g_cvarIRC_Enabled.BoolValue) {
			ServerCommand("irc_send PRIVMSG #%s :%s changed name to %s", g_sIRC_Main, g_sOldName[client], new_name);
		}
		char color[8];
		switch (GetClientTeam(client)) {
			case TFTeam_Red: {
				strcopy(color, sizeof(color), "red");
			}
			case TFTeam_Blue: {
				strcopy(color, sizeof(color), "blue");
			}
			default: {
				strcopy(color, sizeof(color), "default");
			}
		}
		if (g_bChecked[client]) {
			CPrintToChatAll("* {%s}%s{default} changed name to {%s}%s{default}", color, g_sOldName[client], color, new_name);
		}
	}
	else {
		PrintToChatAll("%s connected", new_name);
	}
	g_bChecking[client] = false;
	g_bChecked[client] = true;
	strcopy(g_sOldName[client], MAX_NAME_LENGTH, new_name);
	return Plugin_Handled;
}

// ensures that utf8 names are properly terminated
void TerminateNameUTF8(char[] name) { 
	int len = strlen(name); 

	for (int i = 0; i < len; i++) {
		int bytes = IsCharMB(name[i]);
		if (bytes > 1) {
			if (len - i < bytes) {
				name[i] = '\0';
				return;
			}
			i += bytes - 1;
		}
	}
}

public Action OnClientCommand(int client, int args) {
	if (!g_cvarStatus.BoolValue || !g_cvarCheckCommands.BoolValue) {
		return Plugin_Continue;
	}
	
	char sCommand[255];
	GetCmdArg(0, sCommand, sizeof(sCommand));
	
	if (strlen(sCommand) == 0) {
		return Plugin_Continue;
	}
	
	int begin = 0;
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
	}
	
	if (kv.GotoFirstSubKey()) {
		do {
			char sName[128];
			kv.GetSectionName(sName, sizeof(sName));
			
			StringMap currentsection = new StringMap();
			currentsection.SetString("name", sName);
			
			ParseSectionValues(kv, currentsection);
		} while (kv.GotoNextKey());
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
			currentsection.SetString(sKey, sValue);
		}
		else if (StrEqual(sKey, "warn")) {
			kv.GetString(NULL_STRING, sValue, sizeof(sValue));
			currentsection.SetString(sKey, sValue);
		}
		else if (StrEqual(sKey, "limit")) {
			currentsection.SetValue(sKey, KvGetNum(kv, NULL_STRING));
		}
		else if (StrEqual(sKey, "forgive")) {
			currentsection.SetValue(sKey, KvGetNum(kv, NULL_STRING));
		}
		else if (StrEqual(sKey, "punish")) {
			kv.GetString(NULL_STRING, sValue, sizeof(sValue));
			currentsection.SetString(sKey, sValue);
		}
		else if (StrEqual(sKey, "immunity")) {
			kv.GetString(NULL_STRING, sValue, sizeof(sValue));
			currentsection.SetValue(sKey, ReadFlagString(sValue));
		}
	} while (kv.GotoNextKey(false));
	
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
	
	int flags;
	int a;
	int b;
	int c;
	
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

// ------------------------ Message suppression

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