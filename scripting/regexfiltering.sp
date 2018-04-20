//Pragma
#pragma semicolon 1
#include <morecolors>
#pragma newdecls required

//Defines
#define PLUGIN_DESCRIPTION "Regex filtering for names, chat and commands."
#define PLUGIN_VERSION "2.1.0"

#define MAX_EXPRESSION_LENGTH 256

//Sourcemod Includes
#include <sourcemod>
#include <sourcemod-misc>
#include <regex>

//ConVars
ConVar convar_Status;
ConVar convar_ConfigPath;
ConVar convar_CheckChat;
ConVar convar_CheckCommands;
ConVar convar_CheckNames;
ConVar convar_IRC_Enabled;
ConVar convar_IRC_Main;
ConVar convar_IRC_Filtered;

char sIRC_Main[32];
char sIRC_Filtered[32];

//Globals
bool g_bLate;
bool g_bChanged[MAXPLAYERS+1];

char old_name[MAXPLAYERS+1][MAX_NAME_LENGTH];
char original_name[MAXPLAYERS+1][MAX_NAME_LENGTH];
UserMsg g_umSayText2;

ArrayList g_hArray_Regex_Chat;
ArrayList g_hArray_Regex_Commands;
ArrayList g_hArray_Regex_Names;

StringMap g_hTrie_Limits[MAXPLAYERS+1];

public Plugin myinfo = 
{
	name = "Regex Filters", 
	author = "Keith Warren (Sky Guardian), JoinedSenses", 
	description = PLUGIN_DESCRIPTION, 
	version = PLUGIN_VERSION, 
	url = "https://github.com/SkyGuardian"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_bLate = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	CreateConVar("sm_regexfilters_version", PLUGIN_VERSION, PLUGIN_DESCRIPTION, FCVAR_NOTIFY | FCVAR_DONTRECORD | FCVAR_SPONLY);
	convar_Status = CreateConVar("sm_regexfilters_status", "1", "Status of the plugin.\n(1 = on, 0 = off)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	convar_ConfigPath = CreateConVar("sm_regexfilters_config_path", "configs/regexfilters/", "Location to store the regex filters at.", FCVAR_NOTIFY);
	convar_CheckChat = CreateConVar("sm_regexfilters_check_chat", "1", "Filter out and check chat messages.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	convar_CheckCommands = CreateConVar("sm_regexfilters_check_commands", "1", "Filter out and check commands.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	convar_CheckNames = CreateConVar("sm_regexfilters_check_names", "1", "Filter out and check names.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	convar_IRC_Enabled = CreateConVar("sm_regexfilters_irc_enabled", "0", "Enable IRC relay from SourceIRC", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	convar_IRC_Main =  CreateConVar("sm_regexfilters_irc_main", "", "Main channel for connect message relay", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	convar_IRC_Filtered =  CreateConVar("sm_regexfilters_irc_filtered", "", "Main channel for connect message relay", FCVAR_NOTIFY, true, 0.0, true, 1.0);

	g_umSayText2 = GetUserMessageId("SayText2");
	HookUserMessage(g_umSayText2, UserMessageHook, true);
	
	g_hArray_Regex_Chat = CreateArray(2);
	g_hArray_Regex_Commands = CreateArray(2);
	g_hArray_Regex_Names = CreateArray(2);
	
	HookEvent("player_connect_client", Event_PlayerConnect, EventHookMode_Pre);
	HookEvent("player_changename", Event_OnChangeName, EventHookMode_Pre);
	//RegAdminCmd("sm_testname", Command_TestName, ADMFLAG_ROOT);
}

//public Action Command_TestName(int client, int args)
//{
//	char sName[MAX_NAME_LENGTH];
//	GetCmdArgString(sName, sizeof(sName));
//	
//	Action value = CheckClientName(client, null, sName);
//	PrintToDrixevel("action value: %i", value);
//	return Plugin_Handled;
//}

public void OnConfigsExecuted()
{
	if (!GetConVarBool(convar_Status))
	{
		return;
	}
	
	GetConVarString(convar_IRC_Main, sIRC_Main, sizeof(sIRC_Main));
	GetConVarString(convar_IRC_Filtered, sIRC_Filtered, sizeof(sIRC_Filtered));
	
	char sConfigPath[PLATFORM_MAX_PATH];
	GetConVarString(convar_ConfigPath, sConfigPath, sizeof(sConfigPath));
	
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), sConfigPath);
	
	char sBaseConfig[PLATFORM_MAX_PATH];
	FormatEx(sBaseConfig, sizeof(sBaseConfig), "%s/regexfilters.cfg", sPath);
	LoadExpressions(sBaseConfig);
	
	char sMap[64];
	GetCurrentMap(sMap, sizeof(sMap));
	
	char sMapConfig[PLATFORM_MAX_PATH];
	FormatEx(sBaseConfig, sizeof(sBaseConfig), "%s/maps/regexfilters_%s.cfg", sPath, sMap);
	LoadExpressions(sMapConfig);
	
	CreateTimer(2.0, Timer_DelayLate, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_DelayLate(Handle timer)
{
	if (g_bLate)
	{
		if (g_hTrie_Limits[0] == null)
		{
			g_hTrie_Limits[0] = CreateTrie();
		}
		
		//for (int i = 1; i <= MaxClients; i++)
		//{
		//	if (IsClientInGame(i))
		//	{
		//		OnClientPutInServer(i);
		//	}
		//}
		
		g_bLate = false;
	}
}

public void OnMapStart()
{
	g_hTrie_Limits[0] = CreateTrie();
}

public void OnMapEnd()
{
	delete g_hTrie_Limits[0];
}
public Action Event_PlayerConnect(Event event, const char[] name, bool dontBroadcast)
{
	event.BroadcastDisabled = true;
	
	return Plugin_Continue;
}
public Action UserMessageHook(UserMsg msg_hd, BfRead bf, const int[] players, int playersNum, bool reliable, bool init)
{
    char sMessage[96];
    BfReadString(bf, sMessage, sizeof(sMessage));
    BfReadString(bf, sMessage, sizeof(sMessage));
    if (StrContains(sMessage, "Name_Change") != -1)
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i))
            {
                return Plugin_Handled;
            }
        }
    }
    return Plugin_Continue;
}
public void OnClientAuthorized(int client, const char[] auth)
{
	if (!GetConVarBool(convar_Status))
	{
		return;
	}
	g_hTrie_Limits[client] = CreateTrie();
	g_bChanged[client] = false;
	if (GetConVarBool(convar_CheckNames))
	{
		char sName[MAX_NAME_LENGTH];
		GetClientName(client, sName, sizeof(sName));
		strcopy(original_name[client], MAX_NAME_LENGTH, sName);
		
		CheckClientName(client, null, sName);
	}

	char clientname[32];
	GetClientName(client, clientname, sizeof(clientname));
	PrintToChatAll("%s connected", clientname);
}

public void OnClientDisconnect(int client)
{
	delete g_hTrie_Limits[client];
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	if (!GetConVarBool(convar_Status) || !GetConVarBool(convar_CheckChat))
	{
		return Plugin_Continue;
	}
	
	char sMessage[255];
	strcopy(sMessage, sizeof(sMessage), sArgs);
	
	if (strlen(sMessage) == 0)
	{
		return Plugin_Continue;
	}
	
	int begin;
	int end = GetArraySize(g_hArray_Regex_Chat);
	RegexError errorcode = REGEX_ERROR_NONE;
	bool changed;
	
	Handle save[2];
	Regex regex;
	StringMap currentsection;
	
	any value;
	char sValue[256];
	
	while (begin != end)
	{
		GetArrayArray(g_hArray_Regex_Chat, begin, save, sizeof(save));
		regex = view_as<Regex>(save[0]);
		currentsection = view_as<StringMap>(save[1]);
		
		value = MatchRegex(regex, sMessage, errorcode);
		
		if (value > 0 && errorcode == REGEX_ERROR_NONE)
		{
			if (GetTrieValue(currentsection, "immunity", value) && CheckCommandAccess(client, "", value, true))
			{
				return Plugin_Continue;
			}
			
			if (GetTrieString(currentsection, "warn", sValue, sizeof(sValue)))
			{
				CPrintToChat(client, "[{red}Filter{default}] {lightgreen}%s{default}", sValue);
			}
			
			if (GetTrieString(currentsection, "action", sValue, sizeof(sValue)))
			{
				ParseAndExecute(client, sValue, sizeof(sValue));
			}
			
			if (GetTrieValue(currentsection, "limit", value))
			{
				FormatEx(sValue, sizeof(sValue), "%i", regex);
				
				any at;
				GetTrieValue(g_hTrie_Limits[client], sValue, at);
				
				int mod;
				if (GetTrieValue(currentsection, "forgive", mod))
				{
					FormatEx(sValue, sizeof(sValue), "%i-limit", regex);
					
					float date;
					if (!GetTrieValue(g_hTrie_Limits[client], sValue, date))
					{
						date = GetGameTime();
						SetTrieValue(g_hTrie_Limits[client], sValue, date);
					}
					
					date = GetGameTime() - date;
					at = at - (RoundToCeil(date) & mod);
				}
				
				SetTrieValue(g_hTrie_Limits[client], sValue, at);
				
				if (at > value)
				{
					if (GetTrieString(currentsection, "punish", sValue, sizeof(sValue)))
					{
						ParseAndExecute(client, sValue, sizeof(sValue));
					}
					
					return Plugin_Handled;
				}
			}
			
			if (GetTrieValue(currentsection, "block", value) && view_as<bool>(value))
			{
				char sName[32];
				GetClientName(client, sName, sizeof(sName));
				if (StrContains(sMessage, "`") != -1)
					ReplaceString(sMessage, sizeof(sMessage), "`", "´");
				if (GetConVarBool(convar_IRC_Enabled))
				{
					PrintToChat(client, "Filtered and sent to %s", sIRC_Filtered);
					ServerCommand("irc_send PRIVMSG #%s :%s: `%s`", sIRC_Filtered, sName, sMessage);
				}
				return Plugin_Handled;
			}
			
			if (GetTrieValue(currentsection, "replace", value))
			{
				changed = true;
				int random = GetRandomInt(0, GetArraySize(value) - 1);
				
				DataPack pack = GetArrayCell(value, random);
				
				ResetPack(pack);
				Regex regex2 = ReadPackCell(pack);
				ReadPackString(pack, sValue, sizeof(sValue));
				
				if (regex2 == null)
				{
					regex2 = regex;
				}
				
				random = MatchRegex(regex2, sMessage, errorcode);
				
				if (random > 0 && errorcode == REGEX_ERROR_NONE)
				{
					char[][] sArray = new char[random][256];
					
					for (int a = 0; a < random; a++)
					{
						GetRegexSubString(regex2, a, sArray[a], sizeof(sValue));
					}
					
					for (int a = 0; a < random; a++)
					{
						ReplaceString(sMessage, sizeof(sMessage), sArray[a], sValue);
					}
					
					begin = 0;
				}
			}
		}
		
		begin++;
	}
	
	if (changed)
	{
		if (IsClientConsole(client))
		{
			ServerCommand("say %s", sMessage);
		}
		else
		{
			FakeClientCommand(client, "%s %s", command, sMessage);
			return Plugin_Handled;
		}
	}
	
	return Plugin_Continue;
}

public Action Event_OnChangeName(Event event, const char[] name, bool dontBroadcast)
{
	event.BroadcastDisabled = true;
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if (!GetConVarBool(convar_Status) || !GetConVarBool(convar_CheckNames) || !IsPlayerIndex(client) || !IsClientConnected(client) || !IsClientInGame(client))
	{
		return Plugin_Continue;
	}

	char sNewName[MAX_NAME_LENGTH];
	GetEventString(event, "newname", sNewName, sizeof(sNewName));
	if(!g_bChanged[client])
	{
		strcopy(original_name[client],MAX_NAME_LENGTH, sNewName);
	}
	CheckClientName(client, event, sNewName);
	
	return Plugin_Handled;
}
Action CheckClientName(int client, Event event, char[] new_name)
{
	int begin;
	int end = GetArraySize(g_hArray_Regex_Names);
	RegexError errorcode = REGEX_ERROR_NONE;
	bool changed;
	
	Handle save[2];
	Regex regex;
	StringMap currentsection;
	
	any value;
	char sValue[256];
	
	while (begin != end)
	{
		GetArrayArray(g_hArray_Regex_Names, begin, save, sizeof(save));
		regex = view_as<Regex>(save[0]);
		currentsection = view_as<StringMap>(save[1]);
		
		value = MatchRegex(regex, new_name, errorcode);
		
		if (value > 0 && errorcode == REGEX_ERROR_NONE)
		{
			if (GetTrieValue(currentsection, "immunity", value) && CheckCommandAccess(client, "", value, true))
			{
				return Plugin_Continue;
			}
			
			if (GetTrieString(currentsection, "warn", sValue, sizeof(sValue)))
			{
				CPrintToChat(client, "[{red}Filter{default}] {lightgreen}%s{default}", sValue);
			}
			
			if (GetTrieString(currentsection, "action", sValue, sizeof(sValue)))
			{
				ParseAndExecute(client, sValue, sizeof(sValue));
			}
			
			if (GetTrieValue(currentsection, "limit", value))
			{
				FormatEx(sValue, sizeof(sValue), "%i", regex);
				
				any at;
				GetTrieValue(g_hTrie_Limits[client], sValue, at);
				
				int mod;
				if (GetTrieValue(currentsection, "forgive", mod))
				{
					FormatEx(sValue, sizeof(sValue), "%i-limit", regex);
					
					float date;
					if (!GetTrieValue(g_hTrie_Limits[client], sValue, date))
					{
						date = GetGameTime();
						SetTrieValue(g_hTrie_Limits[client], sValue, date);
					}
					
					date = GetGameTime() - date;
					at = at - (RoundToCeil(date) & mod);
				}
				
				SetTrieValue(g_hTrie_Limits[client], sValue, at);
				
				if (at > value)
				{
					if (GetTrieString(currentsection, "punish", sValue, sizeof(sValue)))
					{
						ParseAndExecute(client, sValue, sizeof(sValue));
					}
					
					return Plugin_Handled;
				}
			}
			
			if (GetTrieValue(currentsection, "block", value) && view_as<bool>(value))
			{
				return Plugin_Handled;
			}
			
			if (GetTrieValue(currentsection, "replace", value))
			{
				changed = true;
				g_bChanged[client] = true;
				int random = GetRandomInt(0, GetArraySize(value) - 1);
				
				DataPack pack = GetArrayCell(value, random);
				
				ResetPack(pack);
				Regex regex2 = ReadPackCell(pack);
				ReadPackString(pack, sValue, sizeof(sValue));

				if (regex2 == null)
				{
					regex2 = regex;
				}
				
				random = MatchRegex(regex2, new_name, errorcode);
				
				if (random > 0 && errorcode == REGEX_ERROR_NONE)
				{
					char[][] sArray = new char[random][256];
					
					for (int a = 0; a < random; a++)
					{
						GetRegexSubString(regex2, a, sArray[a], sizeof(sValue));
					}	
					for (int a = 0; a < random; a++)
					{
						if (StrEqual(sValue, "remove", false))
						{
							ReplaceString(new_name, MAX_NAME_LENGTH, sArray[a], "");
						}
						else
						{
							ReplaceString(new_name, MAX_NAME_LENGTH, sArray[a], sValue);
						}
					}
					
					begin = 0;
				}
			}
		}
		
		begin++;
	}

	if (changed)
	{
		TerminateNameUTF8(new_name);
		if (StrEqual(new_name, "", false))
			strcopy(new_name, MAX_NAME_LENGTH, "unnamed");		
		SetClientName(client, new_name);
		if (StrContains(original_name[client], "`") != -1)
			ReplaceString(original_name[client], MAX_NAME_LENGTH, "`", "´");
		if (StrContains(new_name, "`") != -1)
			ReplaceString(new_name, MAX_NAME_LENGTH, "`", "´");
		if (GetConVarBool(convar_IRC_Enabled))
			ServerCommand("irc_send PRIVMSG #%s :`%s`  -->  `%s`", sIRC_Filtered, original_name[client], new_name);
		GetClientName(client, old_name[client], MAX_NAME_LENGTH);
		return Plugin_Handled;
	}
	else
	{
		if (IsClientInGame(client))
		{
			if (StrEqual(old_name[client], new_name))
			{
				return Plugin_Continue;
			} 
			if (GetConVarBool(convar_IRC_Enabled))
				ServerCommand("irc_send PRIVMSG #%s :%s changed name to %s", sIRC_Main, old_name[client], new_name);
			if (view_as<TFTeam>(GetClientTeam(client)) == TFTeam_Red)
			{
				CPrintToChatAll("* {red}%s{default} changed name to {red}%s{default}", old_name[client], new_name);
			}
			else if (view_as<TFTeam>(GetClientTeam(client)) == TFTeam_Blue)
			{
				CPrintToChatAll("* {blue}%s{default} changed name to {blue}%s{default}", old_name[client], new_name);
			}
			else if (view_as<TFTeam>(GetClientTeam(client)) == TFTeam_Spectator)
			{
				CPrintToChatAll("* %s changed name to %s", old_name[client], new_name);
			}
		}
	}
	strcopy(old_name[client], MAX_NAME_LENGTH, new_name);
	g_bChanged[client] = false;
	return Plugin_Handled;
}

void TerminateNameUTF8(char[] name) // ensures that utf8 names are properly terminated
{ 
	int len = strlen(name); 
	
	for (int i = 0; i < len; i++) 
	{ 
		int bytes = IsCharMB(name[i]); 
		
		if (bytes > 1) 
		{ 
			if (len - i < bytes) 
			{ 
				name[i] = '\0'; 
				return; 
			} 
			
			i += bytes - 1; 
		} 
	} 
}

public Action OnClientCommand(int client, int args)
{
	if (!GetConVarBool(convar_Status) || !GetConVarBool(convar_CheckCommands))
	{
		return Plugin_Continue;
	}
	
	char sCommand[255];
	GetCmdArg(0, sCommand, sizeof(sCommand));
	
	if (strlen(sCommand) == 0)
	{
		return Plugin_Continue;
	}
	
	int begin;
	int end = GetArraySize(g_hArray_Regex_Commands);
	RegexError errorcode = REGEX_ERROR_NONE;
	bool changed;
	
	Handle save[2];
	Regex regex;
	StringMap currentsection;
	
	any value;
	char sValue[256];
	
	while (begin != end)
	{
		GetArrayArray(g_hArray_Regex_Commands, begin, save, sizeof(save));
		regex = view_as<Regex>(save[0]);
		currentsection = view_as<StringMap>(save[1]);
		
		value = MatchRegex(regex, sCommand, errorcode);
		
		if (value > 0 && errorcode == REGEX_ERROR_NONE)
		{
			if (GetTrieValue(currentsection, "immunity", value) && CheckCommandAccess(client, "", value, true))
			{
				return Plugin_Continue;
			}
			
			if (GetTrieString(currentsection, "warn", sValue, sizeof(sValue)))
			{
				ReplyToCommand(client, "[Filter] %s", sValue);
			}
			
			if (GetTrieString(currentsection, "action", sValue, sizeof(sValue)))
			{
				ParseAndExecute(client, sValue, sizeof(sValue));
			}
			
			if (GetTrieValue(currentsection, "limit", value))
			{
				FormatEx(sValue, sizeof(sValue), "%i", regex);
				
				any at;
				GetTrieValue(g_hTrie_Limits[client], sValue, at);
				
				int mod;
				if (GetTrieValue(currentsection, "forgive", mod))
				{
					FormatEx(sValue, sizeof(sValue), "%i-limit", regex);
					
					float date;
					if (!GetTrieValue(g_hTrie_Limits[client], sValue, date))
					{
						date = GetGameTime();
						SetTrieValue(g_hTrie_Limits[client], sValue, date);
					}
					
					date = GetGameTime() - date;
					at = at - (RoundToCeil(date) & mod);
				}
				
				SetTrieValue(g_hTrie_Limits[client], sValue, at);
				
				if (at > value)
				{
					if (GetTrieString(currentsection, "punish", sValue, sizeof(sValue)))
					{
						ParseAndExecute(client, sValue, sizeof(sValue));
					}
					
					return Plugin_Handled;
				}
			}
			
			if (GetTrieValue(currentsection, "block", value) && view_as<bool>(value))
			{
				return Plugin_Handled;
			}
			
			if (GetTrieValue(currentsection, "replace", value))
			{
				changed = true;
				int random = GetRandomInt(0, GetArraySize(value) - 1);
				
				DataPack pack = GetArrayCell(value, random);
				
				ResetPack(pack);
				Regex regex2 = ReadPackCell(pack);
				ReadPackString(pack, sValue, sizeof(sValue));
				
				if (regex2 == null)
				{
					regex2 = regex;
				}
				
				random = MatchRegex(regex2, sCommand, errorcode);
				
				if (random > 0 && errorcode == REGEX_ERROR_NONE)
				{
					char[][] sArray = new char[random][256];
					
					for (int a = 0; a < random; a++)
					{
						GetRegexSubString(regex2, a, sArray[a], sizeof(sValue));
					}
					
					for (int a = 0; a < random; a++)
					{
						ReplaceString(sCommand, sizeof(sCommand), sArray[a], sValue);
					}
					
					begin = 0;
				}
			}
		}
		
		begin++;
	}
	
	if (changed)
	{
		if (IsClientConsole(client))
		{
			ServerCommand("%s", sCommand);
		}
		else
		{
			FakeClientCommand(client, "%s", sCommand);
			return Plugin_Handled;
		}
	}
	
	return Plugin_Continue;
}

void ParseAndExecute(int client, char[] command, int size)
{
	char sReplace[256];
	
	if (IsClientConsole(client))
	{
		FormatEx(sReplace, sizeof(sReplace), "0");
	}
	else
	{
		FormatEx(sReplace, sizeof(sReplace), "%i", GetClientUserId(client));
	}
	
	ReplaceString(command, size, "%u", sReplace);
	
	if (!IsClientConsole(client))
	{
		FormatEx(sReplace, sizeof(sReplace), "%i", client);
	}
	
	ReplaceString(command, size, "%i", sReplace);
	
	GetClientName(client, sReplace, sizeof(sReplace));
	ReplaceString(command, size, "%n", sReplace);
	
	ServerCommand(command);
}

void LoadExpressions(const char[] file)
{
	KeyValues kv = CreateKeyValues("RegexFilters");
	
	if (FileExists(file))
	{
		FileToKeyValues(kv, file);
	}
	{
		KeyValuesToFile(kv, file);
	}
	
	if (KvGotoFirstSubKey(kv))
	{
		do
		{
			char sName[128];
			KvGetSectionName(kv, sName, sizeof(sName));
			
			StringMap currentsection = CreateTrie();
			SetTrieString(currentsection, "name", sName);
			
			ParseSectionValues(kv, currentsection);
		}
		while (KvGotoNextKey(kv));
	}
	
	delete kv;
}

void ParseSectionValues(KeyValues kv, StringMap currentsection)
{
	if (!KvGotoFirstSubKey(kv, false))
	{
		return;
	}
	
	do
	{
		char sKey[128];
		KvGetSectionName(kv, sKey, sizeof(sKey));
		
		char sValue[128];
		
		if (StrEqual(sKey, "chatpattern"))
		{
			KvGetString(kv, NULL_STRING, sValue, sizeof(sValue));
			RegisterExpression(sValue, currentsection, g_hArray_Regex_Chat);
		}
		else if (StrEqual(sKey, "cmdpattern") || StrEqual(sKey, "commandkeyword"))
		{
			KvGetString(kv, NULL_STRING, sValue, sizeof(sValue));
			RegisterExpression(sValue, currentsection, g_hArray_Regex_Commands);
		}
		else if (StrEqual(sKey, "namepattern"))
		{
			KvGetString(kv, NULL_STRING, sValue, sizeof(sValue));
			RegisterExpression(sValue, currentsection, g_hArray_Regex_Names);
		}
		else if (StrEqual(sKey, "replace"))
		{
			any value;
			if (!GetTrieValue(currentsection, "replace", value))
			{
				value = CreateArray();
				SetTrieValue(currentsection, "replace", value);
			}
			
			KvGetString(kv, NULL_STRING, sValue, sizeof(sValue));
			AddReplacement(sValue, value);
		}
		else if (StrEqual(sKey, "replacepattern"))
		{
			any value;
			if (!GetTrieValue(currentsection, "replace", value))
			{
				value = CreateArray();
				SetTrieValue(currentsection, "replace", value);
			}
			
			KvGetString(kv, NULL_STRING, sValue, sizeof(sValue));
			AddPatternReplacement(sValue, value);
		}
		else if (StrEqual(sKey, "block"))
		{
			SetTrieValue(currentsection, sKey, KvGetNum(kv, NULL_STRING));
		}
		else if (StrEqual(sKey, "action"))
		{
			KvGetString(kv, NULL_STRING, sValue, sizeof(sValue));
			SetTrieString(currentsection, sKey, sValue);
		}
		else if (StrEqual(sKey, "warn"))
		{
			KvGetString(kv, NULL_STRING, sValue, sizeof(sValue));
			SetTrieString(currentsection, sKey, sValue);
		}
		else if (StrEqual(sKey, "limit"))
		{
			SetTrieValue(currentsection, sKey, KvGetNum(kv, NULL_STRING));
		}
		else if (StrEqual(sKey, "forgive"))
		{
			SetTrieValue(currentsection, sKey, KvGetNum(kv, NULL_STRING));
		}
		else if (StrEqual(sKey, "punish"))
		{
			KvGetString(kv, NULL_STRING, sValue, sizeof(sValue));
			SetTrieString(currentsection, sKey, sValue);
		}
		else if (StrEqual(sKey, "immunity"))
		{
			KvGetString(kv, NULL_STRING, sValue, sizeof(sValue));
			SetTrieValue(currentsection, sKey, ReadFlagString(sValue));
		}
	}
	while (KvGotoNextKey(kv, false));
	
	KvGoBack(kv);
}

void RegisterExpression(const char[] key, StringMap currentsection, ArrayList data)
{
	char sExpression[MAX_EXPRESSION_LENGTH];
	int flags = ParseExpression(key, sExpression, sizeof(sExpression));
	
	if (flags == -1)
	{
		return;
	}
	
	char sError[128];
	RegexError errorcode;
	Regex regex = CompileRegex(sExpression, flags, sError, sizeof(sError), errorcode);
	
	if (regex == null)
	{
		LogError("Error compiling expression '%s' with flags '%i': [%i] %s", sExpression, flags, errorcode, sError);
		return;
	}
	
	Handle save[2];
	save[0] = view_as<Handle>(regex);
	save[1] = view_as<Handle>(currentsection);
	
	PushArrayArray(data, save, sizeof(save));
}

int ParseExpression(const char[] key, char[] expression, int size)
{
	strcopy(expression, size, key);
	TrimString(expression);
	
	int flags;
	int a;
	int b;
	int c;
	
	if (expression[strlen(expression) - 1] == '\'')
	{
		for (; expression[flags] != '\0'; flags++)
		{
			if (expression[flags] == '\'')
			{
				a++;
				b = c;
				c = flags;
			}
		}
		
		if (a < 2)
		{
			LogError("Regex Filter line malformed: %s", key);
			return -1;
		}
		else
		{
			expression[b] = '\0';
			expression[c] = '\0';
			flags = FindRegexFlags(expression[b + 1]);
			
			TrimString(expression);
			
			if (a > 2 && expression[0] == '\'')
			{
				strcopy(expression, strlen(expression) - 1, expression[1]);
			}
		}
	}
	
	return flags;
}

int FindRegexFlags(const char[] flags)
{
	char sBuffer[7][16];
	ExplodeString(flags, "|", sBuffer, 7, 16);
	
	int new_flags;
	for (int i = 0; i < 7; i++)
	{
		if (sBuffer[i][0] == '\0')
		{
			continue;
		}
		
		if (StrEqual(sBuffer[i], "CASELESS"))
		{
			new_flags |= PCRE_CASELESS;
		}
		else if (StrEqual(sBuffer[i], "MULTILINE"))
		{
			new_flags |= PCRE_MULTILINE;
		}
		else if (StrEqual(sBuffer[i], "DOTALL"))
		{
			new_flags |= PCRE_DOTALL;
		}
		else if (StrEqual(sBuffer[i], "EXTENDED"))
		{
			new_flags |= PCRE_EXTENDED;
		}
		else if (StrEqual(sBuffer[i], "UNGREEDY"))
		{
			new_flags |= PCRE_UNGREEDY;
		}
		else if (StrEqual(sBuffer[i], "UTF8"))
		{
			new_flags |= PCRE_UTF8;
		}
		else if (StrEqual(sBuffer[i], "NO_UTF8_CHECK"))
		{
			new_flags |= PCRE_NO_UTF8_CHECK;
		}
	}
	
	return new_flags;
}

void AddReplacement(const char[] value, ArrayList data)
{
	DataPack pack = CreateDataPack();
	WritePackCell(pack, view_as<Handle>(null));
	WritePackString(pack, value);
	
	PushArrayCell(data, pack);
}

void AddPatternReplacement(const char[] value, ArrayList data)
{
	char sExpression[MAX_EXPRESSION_LENGTH];
	int flags = ParseExpression(value, sExpression, sizeof(sExpression));
	
	if (flags == -1)
	{
		return;
	}
	
	char sError[128];
	RegexError errorcode;
	Regex regex = CompileRegex(sExpression, flags, sError, sizeof(sError), errorcode);
	
	if (regex == null)
	{
		LogError("Error compiling expression '%s' with flags '%i': [%i] %s", sExpression, flags, errorcode, sError);
		return;
	}
	
	DataPack pack = CreateDataPack();
	WritePackCell(pack, regex);
	WritePackString(pack, "");
	
	PushArrayCell(data, pack);
}