#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <SteamWorks>

ConVar g_cDebug = null;
ConVar g_cInterval = null;
ConVar g_cMessage = null;
ConVar g_cAmount = null;
ConVar g_cURL = null;

public void OnPluginStart()
{
    g_cDebug = CreateConVar("version_debug", "0", "Enable debug mode?", _, true, 0.0, true, 1.0);
    g_cInterval = CreateConVar("version_interval", "30.0", "In which interval should we check for new updates?", _, true, 30.0);
    g_cMessage = CreateConVar("version_message", "1", "Print message into servers chat?", _, true, 0.0, true, 1.0);
    g_cAmount = CreateConVar("version_amount", "10", "How much messages should be print?", _, true, 1.0);
    g_cURL = CreateConVar("version_url", "https://raw.githubusercontent.com/SteamDatabase/GameTracking-CSGO/master/csgo/steam.inf", "Raw url to the steam.inf file.");

    AutoExecConfig();
}

public void OnConfigsExecuted()
{
    CreateTimer(g_cInterval.FloatValue, Timer_CheckVersion, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
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

        if (g_cMessage.BoolValue)
        {
            for (int i = 1; i <= g_cAmount.IntValue; i++)
            {
                PrintToChatAll("This server seems to be out of date! Local Version: %d (Patch: %d), SteamDB Version: %d (Patch: %d)", iLocalServer, iLocalPatch, iSteamDBServer, iSteamDBPatch);
            }
        }
    }
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
