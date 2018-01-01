#include <sourcemod>


new UserMsg:g_umSayText2;

public OnPluginStart()
{
    g_umSayText2 = GetUserMessageId("SayText2");
    HookUserMessage(g_umSayText2, UserMessageHook, true);
}

public Action:UserMessageHook(UserMsg:msg_hd, Handle:bf, const players[], playersNum, bool:reliable, bool:init)
{
    decl String:_sMessage[96];
    BfReadString(bf, _sMessage, sizeof(_sMessage));
    BfReadString(bf, _sMessage, sizeof(_sMessage));
    if (StrContains(_sMessage, "Name_Change") != -1)
    {
        for (new i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i))
            {
                return Plugin_Handled;
            }
        }
    }
    return Plugin_Continue;
}  