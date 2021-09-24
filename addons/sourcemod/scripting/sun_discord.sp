#pragma semicolon 1

#define PLUGIN_DESCRIPTION "Checks every x seconds the server+patch versions from the steam.inf file (locally + steamdb)"
#define PLUGIN_VERSION "1.0.0"

#include <sourcemod>
#include <autoexecconfig>
#include <discord>
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
    Core.Webhook = AutoExecConfig_CreateConVar("sun_discor_webhook_url", "", "Your webhook url. Don't forget to add \"/slack\" at the end.");
    Core.Color = AutoExecConfig_CreateConVar("sun_discord_color", "#7f0000", "Hexcode of the color (with '#' !)");
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

    char sHostname[512];
    ConVar cHostname = FindConVar("hostname");

    if (cHostname == null)
    {
        return;
    }

    cHostname.GetString(sHostname, sizeof(sHostname));
    
    char sName[128];
    Core.Username.GetString(sName, sizeof(sName));

    char sHook[256];
    Core.Webhook.GetString(sHook, sizeof(sHook));

    DiscordWebHook hook = new DiscordWebHook(sHook);
    hook.SlackMode = true;
    hook.SetUsername(sName);

    char sColor[12], sAvatar[512];
    Core.Color.GetString(sColor, sizeof(sColor));
    Core.Avatar.GetString(sAvatar, sizeof(sAvatar));

    char sLocal[16], sSteamDB[16];
    IntToString(iLocalVersion, sLocal, sizeof(sLocal));
    IntToString(iSteamVersion, sSteamDB, sizeof(sLocal));

    MessageEmbed Embed = new MessageEmbed();
    Embed.SetColor(sColor);
    Embed.SetTitle(sHostname);
    Embed.SetAuthorIcon(sAvatar);
    Embed.AddField("Current Version:", sLocal, true);
    Embed.AddField("New Version:", sSteamDB, true);

    hook.Embed(Embed);
    hook.Send();

    delete hook;
}
