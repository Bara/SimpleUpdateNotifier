#pragma semicolon 1

#define PLUGIN_DESCRIPTION "Checks every x seconds the server+patch versions from the steam.inf file (locally + steamdb)"
#define PLUGIN_VERSION "1.0.0"

#include <sourcemod>
#include <autoexecconfig>
#include <discordEmbedAPI>
#include <sun>

#pragma newdecls required

enum struct Global
{
    ConVar Webhook;
    ConVar Color;
    ConVar Avatar;
    ConVar Username;
    ConVar Debug;
}
Global Core;

public Plugin myinfo =
{
    name = "Simple Update Notifier - Discord",
    author = "Bara",
    description = PLUGIN_DESCRIPTION,
    version = PLUGIN_VERSION,
    url = "github.com/Bara"
};

public void OnPluginStart()
{
    CreateConVar("sun_discord_version", PLUGIN_VERSION, PLUGIN_DESCRIPTION, FCVAR_NOTIFY | FCVAR_DONTRECORD | FCVAR_REPLICATED);

    AutoExecConfig_SetCreateDirectory(true);
    AutoExecConfig_SetCreateFile(true);
    AutoExecConfig_SetFile("sun.discord");
    Core.Webhook = AutoExecConfig_CreateConVar("sun_discord_webhook_url", "", "Your webhook url. Don't(!) add \"/slack\" at the end.", FCVAR_PROTECTED);
    Core.Color = AutoExecConfig_CreateConVar("sun_discord_color", "8323072", "Hexcode of the color as integer(!).");
    Core.Avatar = AutoExecConfig_CreateConVar("sun_discord_avatar", "https://bara.dev/images/sun.png", "URL to Avatar image");
    Core.Username = AutoExecConfig_CreateConVar("sun_discord_username", "Simple Update Notifier", "Discord username");
    AutoExecConfig_ExecuteFile();
    AutoExecConfig_CleanFile();
}

public void OnConfigsExecuted()
{
    Core.Debug = FindConVar("sun_debug");
}

public void SUN_OnUpdate(int iLocalVersion, int iSteamVersion)
{
    if (Core.Debug != null && Core.Debug.BoolValue)
    {
        LogMessage("SUN_OnUpdate called!");
    }

    ConVar cHostname = FindConVar("hostname");

    if (cHostname == null)
    {
        return;
    }

    Webhook webhook = new Webhook();
    
    char sName[128];
    Core.Username.GetString(sName, sizeof(sName));
    webhook.SetUsername(sName);

    char sAvatar[512];
    Core.Avatar.GetString(sAvatar, sizeof(sAvatar));
    webhook.SetAvatarURL(sAvatar);

    char sLocal[16], sSteamDB[16];
    IntToString(iLocalVersion, sLocal, sizeof(sLocal));
    IntToString(iSteamVersion, sSteamDB, sizeof(sLocal));

    char sHostname[512];
    cHostname.GetString(sHostname, sizeof(sHostname));

    Embed embed = new Embed();
    embed.SetColor(Core.Color.IntValue);
    embed.SetTitle(sHostname);
    embed.SetDescription("Server is out of date");
    
    EmbedField eServerVersion = new EmbedField();
    eServerVersion.SetName("Current Version");
    eServerVersion.SetValue(sLocal);
    eServerVersion.SetInline(true);

    EmbedField eValveVersion = new EmbedField();
    eValveVersion.SetName("New Version");
    eValveVersion.SetValue(sSteamDB);
    eValveVersion.SetInline(true);
    
    embed.AddField(eServerVersion);
    embed.AddField(eValveVersion);

    char sHook[256];
    Core.Webhook.GetString(sHook, sizeof(sHook));
    webhook.Execute(sHook, OnWebHookExecuted);
}

public void OnWebHookExecuted(HTTPResponse response, DataPack pack)
{
    if (response.Status != HTTPStatus_NoContent)
    {
        LogError("An error has occured while sending the webhook.");
        return;
    }
}
