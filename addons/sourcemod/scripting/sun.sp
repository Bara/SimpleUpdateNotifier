#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_DESCRIPTION "Checks every x seconds the server+patch versions from the steam.inf file (locally + steamdb)"
#define PLUGIN_VERSION "1.0.0"

#include <sourcemod>
#include <SteamWorks>
#include <autoexecconfig>

enum struct Global
{
    ConVar Debug;
    ConVar Interval;
    ConVar Message;
    ConVar Amount;
    ConVar URL;
    ConVar Restart;
    ConVar RestartMessage;
    ConVar RestartPlayers;
    ConVar RestartPercent;
    ConVar Delay;
    ConVar MaxVisible;

    GlobalForward OnUpdate;

    bool Send;
}

Global Core;

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
    Core.OnUpdate = new GlobalForward("SUN_OnUpdate", ET_Ignore, Param_Cell, Param_Cell);

    RegPluginLibrary("sun");

    return APLRes_Success;
}

public void OnPluginStart()
{
    CreateConVar("sun_version", PLUGIN_VERSION, PLUGIN_DESCRIPTION, FCVAR_NOTIFY | FCVAR_DONTRECORD | FCVAR_REPLICATED);

    AutoExecConfig_SetCreateDirectory(true);
    AutoExecConfig_SetCreateFile(true);
    AutoExecConfig_SetFile("sun.core");
    Core.Debug = AutoExecConfig_CreateConVar("sun_debug", "0", "Enable debug mode?", _, true, 0.0, true, 1.0);
    Core.Interval = AutoExecConfig_CreateConVar("sun_interval", "300", "In which interval should we check for new updates?", _, true, 60.0);
    Core.Message = AutoExecConfig_CreateConVar("sun_message", "1", "Print message into servers chat?", _, true, 0.0, true, 1.0);
    Core.Amount = AutoExecConfig_CreateConVar("sun_amount", "10", "How much messages should be print?", _, true, 1.0);
    Core.URL = AutoExecConfig_CreateConVar("sun_url", "https://raw.githubusercontent.com/SteamDatabase/GameTracking-CSGO/master/csgo/steam.inf", "Raw url to the steam.inf file.");
    Core.Restart = AutoExecConfig_CreateConVar("sun_restart", "0", "Restart server on update?", _, true, 0.0, true, 1.0);
    Core.RestartMessage = AutoExecConfig_CreateConVar("sun_restart_message", "0", "Print message when restart is planned? sun_restart must be 1", _, true, 0.0, true, 1.0);
    Core.RestartPlayers = AutoExecConfig_CreateConVar("sun_restart_players", "-1", "Restart the server with a amount of X players or less. (-1 to disable this feature)", _, true, -1.0);
    Core.RestartPercent = AutoExecConfig_CreateConVar("sun_restart_percent", "0", "Restart the server with a amount of X% players or less. (0 to disable this feature)", _, true, 0.0);
    Core.Delay = AutoExecConfig_CreateConVar("sun_delay", "5.0", "After how much seconds restart the server?", _, true, 0.0);
    AutoExecConfig_ExecuteFile();
    AutoExecConfig_CleanFile();
}

public void OnConfigsExecuted()
{
    if (Core.Debug.BoolValue)
    {
        LogMessage("Sun timer started.");
    }

    Core.Send = false;

    CreateTimer(Core.Interval.FloatValue, Timer_CheckVersion, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);

    Core.MaxVisible = FindConVar("sv_visiblemaxplayers");
}

public void OnMapStart()
{
    Core.Send = false;
}

public Action Timer_CheckVersion(Handle timer)
{
    if (Core.Debug.BoolValue)
    {
        LogMessage("Timer_CheckVersion called");
    }

    Download_SteamDBSteamINF();

    return Plugin_Continue;
}

void Download_SteamDBSteamINF()
{
    char sURL[128];
    Core.URL.GetString(sURL, sizeof(sURL));

    if (Core.Debug.BoolValue)
    {
        LogMessage("URL: %s", sURL);
    }

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
        SetFailState("SteamWorks error. StatusCode %d RequestSuccessful: %d, Failure: %d", eStatusCode, bRequestSuccessful, bFailure);
    }
    
    delete hRequest;
}

int CheckVersions()
{
    int iLocal = GetLocalVersions();

    int iServer = GetSteamDBVersions();

    if (Core.Debug.BoolValue)
    {
        LogMessage("Test1 - %d/%d", iLocal, iServer);
    }

    if (iLocal == -1 || iServer == -1)
    {
        return;
    }

    if (Core.Debug.BoolValue)
    {
        LogMessage("Test 2");
    }

    if (iLocal == iServer)
    {
        LogMessage("Server seems to be up to date.");
    }
    else
    {
        LogMessage("Server seems to be out of date!");

        if (!Core.Send)
        {
            Call_StartForward(Core.OnUpdate);
            Call_PushCell(iLocal);
            Call_PushCell(iServer);
            Call_Finish();
        }

        Core.Send = true;

        if (Core.Message.BoolValue)
        {
            for (int i = 1; i <= Core.Amount.IntValue; i++)
            {
                PrintToChatAll("This server seems to be out of date! Local Version: %d, SteamDB Version: %d", iLocal, iServer);
            }
        }

        if (Core.Restart.BoolValue && CheckPlayers() && CheckPercent())
        {
            if (Core.RestartMessage.BoolValue)
            {
                PrintToChatAll("Server will be restarting in %.0f seconds...", Core.Delay.FloatValue);
            }

            CreateTimer(Core.Delay.FloatValue, Timer_RestartServer);
        }
    }
}

public Action Timer_RestartServer(Handle timer)
{
    ServerCommand("_restart");
}

int GetLocalVersions()
{
    File fiLocal = OpenFile("steam.inf", "r");

    if (fiLocal == null)
    {
        SetFailState("Can't read steam.inf file!");
        return -1;
    }

    char sLine[48];
    char sLocal[48];

    while (!fiLocal.EndOfFile() && fiLocal.ReadLine(sLine, sizeof(sLine)))
    {
        if (strlen(sLine) > 1)
        {
            if (StrContains(sLine, "PatchVersion" ,false) != -1)
            {
                ReplaceString(sLine, sizeof(sLine), "PatchVersion=", "");
                ReplaceString(sLine, sizeof(sLine), ".", "");
                TrimString(sLine);

                strcopy(sLocal, sizeof(sLocal), sLine);

                break;
            }
        }
    }

    delete fiLocal;

    int iLocal = StringToInt(sLocal);

    if (Core.Debug.BoolValue)
    {
        LogMessage("[Local] PatchVersion: %d (String: %s)", iLocal, sLocal);
    }

    return iLocal;
}

int GetSteamDBVersions()
{
    File fiSteamDB = OpenFile("steamdb_steam.inf", "r");

    if (fiSteamDB == null)
    {
        SetFailState("Can't read steamdb_steam.inf file!");
        return -1;
    }

    char sLine[48];
    char sServer[48];

    while (!fiSteamDB.EndOfFile() && fiSteamDB.ReadLine(sLine, sizeof(sLine)))
    {
        if (strlen(sLine) > 1)
        {
            if (StrContains(sLine, "PatchVersion" ,false) != -1)
            {
                ReplaceString(sLine, sizeof(sLine), "PatchVersion=", "");
                ReplaceString(sLine, sizeof(sLine), ".", "");
                TrimString(sLine);

                strcopy(sServer, sizeof(sServer), sLine);

                break;
            }
        }
    }

    delete fiSteamDB;

    int iServer = StringToInt(sServer);

    if (Core.Debug.BoolValue)
    {
        LogMessage("[SteamDB] PatchVersion: %d (String: %s)", iServer, sServer);
    }

    return iServer;
}

bool CheckPlayers()
{
    if (Core.RestartPlayers.IntValue < 0)
    {
        return true;
    }

    int iCount = 0;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i) && !IsClientSourceTV(i))
        {
            iCount++;
        }
    }

    if (iCount > Core.RestartPlayers.IntValue)
    {
        return false;
    }

    return true;
}

bool CheckPercent()
{
    if (Core.RestartPercent.IntValue == 0)
    {
        return true;
    }

    if (Core.MaxVisible == null)
    {
        Core.MaxVisible = FindConVar("sv_visiblemaxplayers");
    }

    int iSlots = -1;

    if (Core.MaxVisible != null)
    {
        iSlots = Core.MaxVisible.IntValue;
    }

    if (iSlots == -1)
    {
        iSlots = GetMaxHumanPlayers();
    }
    
    int iCount = 0;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i) && !IsClientSourceTV(i))
        {
            iCount++;
        }
    }

    int iPercent = iCount / iSlots * 100;

    if (iPercent > Core.RestartPercent.IntValue)
    {
        return false;
    }

    return true;
}
