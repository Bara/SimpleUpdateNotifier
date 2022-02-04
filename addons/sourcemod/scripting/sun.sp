#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_DESCRIPTION "Checks every x seconds the server+patch versions from the status command (locally + valveapi)"
#define PLUGIN_VERSION "1.0.0"

#include <sourcemod>
#include <regex>
#include <ripext>
#include <autoexecconfig>

enum struct Global
{
    int ServerVersion;
    int ValveVersion;

    ConVar Debug;
    ConVar Interval;
    ConVar Message;
    ConVar Amount;
    ConVar Restart;
    ConVar RestartMessage;
    ConVar RestartPlayers;
    ConVar RestartPercent;
    ConVar Delay;
    ConVar MaxVisible;
    ConVar AppId;
    ConVar Recheck;

    Handle Timer;

    GlobalForward OnUpdate;
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
    Core.Interval = AutoExecConfig_CreateConVar("sun_interval", "120", "In which interval should we check for new updates?", _, true, 60.0);
    Core.Message = AutoExecConfig_CreateConVar("sun_message", "1", "Print message into servers chat?", _, true, 0.0, true, 1.0);
    Core.Amount = AutoExecConfig_CreateConVar("sun_amount", "10", "How much messages should be print?", _, true, 1.0);
    Core.Restart = AutoExecConfig_CreateConVar("sun_restart", "0", "Restart server on update?", _, true, 0.0, true, 1.0);
    Core.RestartMessage = AutoExecConfig_CreateConVar("sun_restart_message", "0", "Print message when restart is planned? sun_restart must be 1", _, true, 0.0, true, 1.0);
    Core.RestartPlayers = AutoExecConfig_CreateConVar("sun_restart_players", "-1", "Restart the server with a amount of X players or less. (-1 to disable this feature)", _, true, -1.0);
    Core.RestartPercent = AutoExecConfig_CreateConVar("sun_restart_percent", "0", "Restart the server with a amount of X% players or less. (0 to disable this feature)", _, true, 0.0);
    Core.Delay = AutoExecConfig_CreateConVar("sun_delay", "5.0", "After how much seconds restart the server?", _, true, 0.0);
    Core.AppId = AutoExecConfig_CreateConVar("sun_appid", "730", "Set the appid of your server. 730 as example for CSGO Server");
    Core.Recheck = AutoExecConfig_CreateConVar("sun_recheck", "1.0", "After getting false version the delay between next version check");
    AutoExecConfig_ExecuteFile();
    AutoExecConfig_CleanFile();
}

public void OnConfigsExecuted()
{
    if (GetServerVersion())
    {
        StartTimer();
    }
    else
    {
        CreateTimer(Core.Recheck.FloatValue, Timer_ReCheck, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
    }

    Core.MaxVisible = FindConVar("sv_visiblemaxplayers");
}

public Action Timer_CheckVersion(Handle timer)
{
    if (Core.Debug.BoolValue)
    {
        LogMessage("Timer_CheckVersion called");
    }

    // Prevent spamming
    if (Core.ServerVersion < Core.ValveVersion)
    {
        CheckVersions();

        return Plugin_Continue;
    }

    GetValveVersion();

    return Plugin_Continue;
}

public Action Timer_ReCheck(Handle timer)
{
    if (GetServerVersion())
    {
        StartTimer();

        return Plugin_Stop;
    }

    return Plugin_Continue;
}

void GetValveVersion()
{
    char sEndpoint[256];
    FormatEx(sEndpoint, sizeof(sEndpoint), "http://api.steampowered.com/ISteamApps/UpToDateCheck/v0001/?appid=%d&version=%d&format=json", Core.AppId.IntValue, Core.ServerVersion);

    HTTPRequest request = new HTTPRequest(sEndpoint);
    request.Get(OnHTTPResponse);
}

public void OnHTTPResponse(HTTPResponse response, any value)
{
    if (response.Status != HTTPStatus_OK) {
        LogMessage("[SUN] Status Code: %d", response.Status);
        return;
    }

    JSONObject jObj = view_as<JSONObject>(view_as<JSONObject>(response.Data).Get("response"));

    if (!jObj.GetBool("success"))
    {
        SetFailState("Valve API sends success->false");
        delete jObj;
        return;
    }

    if (jObj.GetBool("up_to_date"))
    {
        if (Core.Debug.BoolValue)
        {
            LogMessage("Server Version %d is up to date.", Core.ServerVersion);
        }

        Core.ValveVersion = Core.ServerVersion;
        delete jObj;
        return;
    }

    Core.ValveVersion = jObj.GetInt("required_version");
    delete jObj;

    CheckVersions();
}

bool GetServerVersion()
{
    char sBuffer[4096];
    ServerCommandEx(sBuffer, sizeof(sBuffer), "status");

    if (strlen(sBuffer) < 31)
    {
        return false;
    }

    Regex regex = new Regex("^version :.+\\/([0-9]+) [0-9].+$", PCRE_MULTILINE);

    if (regex.Match(sBuffer) != 2)
    {
        delete regex;
        return false;
    }

    char sVersion[12];
    regex.GetSubString(1, sVersion, sizeof(sVersion));
    Core.ServerVersion = StringToInt(sVersion);

    delete regex;

    if (Core.Debug.BoolValue)
    {
        LogMessage("[Local] PatchVersion: %d (String: %s)", Core.ServerVersion, sVersion);
    }

    return true;
}

void CheckVersions()
{
    if (Core.Debug.BoolValue)
    {
        LogMessage("Test1 - %d/%d", Core.ServerVersion, Core.ValveVersion);
    }

    if (Core.ServerVersion == -1 || Core.ValveVersion == -1)
    {
        return;
    }

    if (Core.Debug.BoolValue)
    {
        LogMessage("Test 2");
    }

    if (Core.ServerVersion == Core.ValveVersion)
    {
        LogMessage("Server seems to be up to date.");
    }
    else
    {
        LogMessage("Server seems to be out of date!");

        Call_StartForward(Core.OnUpdate);
        Call_PushCell(Core.ServerVersion);
        Call_PushCell(Core.ValveVersion);
        Call_Finish();

        if (Core.Message.BoolValue)
        {
            for (int i = 1; i <= Core.Amount.IntValue; i++)
            {
                PrintToChatAll("This server seems to be out of date! Server Version: %d, Valve Version: %d", Core.ServerVersion, Core.ValveVersion);
            }
        }

        if (Core.Restart.BoolValue && CheckPlayers() && CheckPercent())
        {
            if (Core.RestartMessage.BoolValue)
            {
                PrintToChatAll("Server will be restarting in %.0f seconds...", Core.Delay.FloatValue);
            }

            LogMessage("Server will be restarting in %.0f seconds...", Core.Delay.FloatValue);
            CreateTimer(Core.Delay.FloatValue, Timer_RestartServer);
        }
    }
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
        if (Core.Debug.BoolValue)
        {
            LogMessage("Players: %d (sun_restart_players is %d)", iCount, Core.RestartPlayers.IntValue);
        }

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

    float fPercent = (float(iCount) / float(iSlots)) * 100.0;

    if (fPercent > Core.RestartPercent.FloatValue)
    {
        if (Core.Debug.BoolValue)
        {
            LogMessage("Players: %d (Slots: %d), Percentage: %.2f (sun_restart_percent is %.2f)", iCount, iSlots, fPercent, Core.RestartPercent.FloatValue);
        }

        return false;
    }

    return true;
}

public Action Timer_RestartServer(Handle timer)
{
    ServerCommand("_restart");

    return Plugin_Stop;
}

void StartTimer()
{
    if (Core.Timer != null)
    {
        LogMessage("Stopping active timer...");
        delete Core.Timer;
    }

    if (Core.Debug.BoolValue)
    {
        LogMessage("Sun timer started.");
    }
    
    Core.Timer = CreateTimer(Core.Interval.FloatValue, Timer_CheckVersion, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}
