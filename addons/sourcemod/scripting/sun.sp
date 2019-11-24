#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_DESCRIPTION "Checks every x seconds the server+patch versions from the steam.inf file (locally + steamdb)"
#define PLUGIN_VERSION "1.0.0"

#include <sourcemod>
#include <SteamWorks>
#include <autoexecconfig>

ConVar g_cDebug = null;
ConVar g_cInterval = null;
ConVar g_cMessage = null;
ConVar g_cAmount = null;
ConVar g_cURL = null;
ConVar g_cRestart = null;
ConVar g_cRestartMessage = null;
ConVar g_cDelay = null;

GlobalForward g_hOnUpdate;

bool g_bSend = false;

public Plugin myinfo =
{
	name = "Simple Update Notifier",
	author = "Bara",
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = "github.com/Bara"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    g_hOnUpdate = new GlobalForward("SUN_OnUpdate", ET_Ignore, Param_Cell, Param_Cell);

    RegPluginLibrary("sun");

    return APLRes_Success;
}

public void OnPluginStart()
{
    CreateConVar("sun_version", PLUGIN_VERSION, PLUGIN_DESCRIPTION, FCVAR_NOTIFY | FCVAR_DONTRECORD | FCVAR_REPLICATED);

    AutoExecConfig_SetCreateDirectory(true);
    AutoExecConfig_SetCreateFile(true);
    AutoExecConfig_SetFile("sun.core");
    g_cDebug = AutoExecConfig_CreateConVar("sun_debug", "0", "Enable debug mode?", _, true, 0.0, true, 1.0);
    g_cInterval = AutoExecConfig_CreateConVar("sun_interval", "30.0", "In which interval should we check for new updates?", _, true, 30.0);
    g_cMessage = AutoExecConfig_CreateConVar("sun_message", "1", "Print message into servers chat?", _, true, 0.0, true, 1.0);
    g_cAmount = AutoExecConfig_CreateConVar("sun_amount", "10", "How much messages should be print?", _, true, 1.0);
    g_cURL = AutoExecConfig_CreateConVar("sun_url", "https://raw.githubusercontent.com/SteamDatabase/GameTracking-CSGO/master/csgo/steam.inf", "Raw url to the steam.inf file.");
    g_cRestart = AutoExecConfig_CreateConVar("sun_restart", "0", "Restart server on update?", _, true, 0.0, true, 1.0);
    g_cRestartMessage = AutoExecConfig_CreateConVar("sun_restart_message", "0", "Print message when restart is planned? sun_restart must be 1", _, true, 0.0, true, 1.0);
    g_cDelay = AutoExecConfig_CreateConVar("sun_delay", "5.0", "After how much seconds restart the server?", _, true, 0.0);
    AutoExecConfig_ExecuteFile();
    AutoExecConfig_CleanFile();
}

public void OnConfigsExecuted()
{
    CreateTimer(g_cInterval.FloatValue, Timer_CheckVersion, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

public void OnMapStart()
{
    g_bSend = false;
}

public Action Timer_CheckVersion(Handle timer)
{
    Download_SteamDBSteamINF();

    return Plugin_Continue;
}

void Download_SteamDBSteamINF()
{
    char sURL[128];
    g_cURL.GetString(sURL, sizeof(sURL));

    Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, sURL);
    SteamWorks_SetHTTPRequestHeaderValue(hRequest, "Pragma", "no-cache");
    SteamWorks_SetHTTPRequestHeaderValue(hRequest, "Cache-Control", "no-cache");
    SteamWorks_SetHTTPCallbacks(hRequest, OnSteamWorksHTTPComplete);
    SteamWorks_SendHTTPRequest(hRequest);
}

public void OnSteamWorksHTTPComplete(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode)
{
    if (bRequestSuccessful && eStatusCode == k_EHTTPStatusCode200OK)
    {
        DeleteFile("steamdb_steam.inf");

        SteamWorks_WriteHTTPResponseBodyToFile(hRequest, "steamdb_steam.inf");

        CheckVersions();
    }
    else
    {
        SetFailState("SteamWorks error (status code %i). Request successful: %s", eStatusCode, bRequestSuccessful);
    }
    
    delete hRequest;
}

int CheckVersions()
{
    int iLocalServer = -1;
    int iLocalPatch = -1;
    GetLocalVersions(iLocalServer, iLocalPatch);

    int iSteamDBServer = -1;
    int iSteamDBPatch = -1;
    GetSteamDBVersions(iSteamDBServer, iSteamDBPatch);

    if (iLocalServer == -1 || iSteamDBServer == -1)
    {
        return;
    }

    if (iLocalServer == iSteamDBServer && iLocalPatch == iSteamDBPatch)
    {
        LogMessage("Server seems to be up to date.");
    }
    else
    {
        LogMessage("Server seems to be out of date!");

        if (!g_bSend)
        {
            Call_StartForward(g_hOnUpdate);
            Call_PushCell(iLocalServer);
            Call_PushCell(iSteamDBServer);
            Call_Finish();
        }

        g_bSend = true;

        if (g_cMessage.BoolValue)
        {
            for (int i = 1; i <= g_cAmount.IntValue; i++)
            {
                PrintToChatAll("This server seems to be out of date! Local Version: %d (Patch: %d), SteamDB Version: %d (Patch: %d)", iLocalServer, iLocalPatch, iSteamDBServer, iSteamDBPatch);
            }
        }

        if (g_cRestart.BoolValue)
        {
            if (g_cRestartMessage.BoolValue)
            {
                PrintToChatAll("Server will be restarting in %.0f seconds...", g_cDelay.FloatValue);
            }

            CreateTimer(g_cDelay.FloatValue, Timer_RestartServer);
        }
    }
}

public Action Timer_RestartServer(Handle timer)
{
    ServerCommand("_restart");
}

void GetLocalVersions(int iLocalServer, int iLocalPatch)
{
    File fiLocal = OpenFile("steam.inf", "r");

    if (fiLocal == null)
    {
        SetFailState("Can't read steam.inf file!");
        return;
    }

    char sLocalLine[48];
    char sLocalServer[48];
    char sLocalPatch[48];

    while (!fiLocal.EndOfFile() && fiLocal.ReadLine(sLocalLine, sizeof(sLocalLine)))
    {
        if (strlen(sLocalLine) > 1)
        {
            if (StrContains(sLocalLine, "PatchVersion" ,false) != -1)
            {
                ReplaceString(sLocalLine, sizeof(sLocalLine), "PatchVersion=", "");
                ReplaceString(sLocalLine, sizeof(sLocalLine), ".", "");

                TrimString(sLocalLine);

                strcopy(sLocalPatch, sizeof(sLocalPatch), sLocalLine);
            }
            else if (StrContains(sLocalLine, "ServerVersion" ,false) != -1)
            {
                ReplaceString(sLocalLine, sizeof(sLocalLine), "ServerVersion=", "");

                TrimString(sLocalLine);

                strcopy(sLocalServer, sizeof(sLocalServer), sLocalLine);
            }
        }
    }

    delete fiLocal;

    iLocalServer = StringToInt(sLocalServer);
    iLocalPatch = StringToInt(sLocalPatch);

    if (g_cDebug.BoolValue)
    {
        LogMessage("[Local] ServerVersion: %d (String: %s)", iLocalServer, sLocalServer);
        LogMessage("[Local] PatchVersion: %d (String: %s)", iLocalPatch, sLocalPatch);
    }
}

void GetSteamDBVersions(int iSteamDBServer, int iSteamDBPatch)
{
    File fiSteamDB = OpenFile("steamdb_steam.inf", "r");

    if (fiSteamDB == null)
    {
        SetFailState("Can't read steamdb_steam.inf file!");
        return;
    }

    char sSteamDBLine[48];
    char sSteamDBServer[48];
    char sSteamDBPatch[48];

    while (!fiSteamDB.EndOfFile() && fiSteamDB.ReadLine(sSteamDBLine, sizeof(sSteamDBLine)))
    {
        if (strlen(sSteamDBLine) > 1)
        {
            if (StrContains(sSteamDBLine, "PatchVersion" ,false) != -1)
            {
                ReplaceString(sSteamDBLine, sizeof(sSteamDBLine), "PatchVersion=", "");
                ReplaceString(sSteamDBLine, sizeof(sSteamDBLine), ".", "");

                TrimString(sSteamDBLine);

                strcopy(sSteamDBPatch, sizeof(sSteamDBPatch), sSteamDBLine);
            }
            else if (StrContains(sSteamDBLine, "ServerVersion" ,false) != -1)
            {
                ReplaceString(sSteamDBLine, sizeof(sSteamDBLine), "ServerVersion=", "");

                TrimString(sSteamDBLine);

                strcopy(sSteamDBServer, sizeof(sSteamDBServer), sSteamDBLine);
            }
        }
    }

    delete fiSteamDB;

    iSteamDBServer = StringToInt(sSteamDBServer);
    iSteamDBPatch = StringToInt(sSteamDBPatch);

    if (g_cDebug.BoolValue)
    {
        LogMessage("[SteamDB] ServerVersion: %d (String: %s)", iSteamDBServer, sSteamDBServer);
        LogMessage("[SteamDB] PatchVersion: %d (String: %s)", iSteamDBPatch, sSteamDBPatch);
    }
}
