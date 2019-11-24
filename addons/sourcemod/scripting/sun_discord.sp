#pragma semicolon 1

#define PLUGIN_DESCRIPTION "Checks every x seconds the server+patch versions from the steam.inf file (locally + steamdb)"
#define PLUGIN_VERSION "1.0.0"

#include <sourcemod>
#include <autoexecconfig>
#include <discord>
#include <sun>

#pragma newdecls required

ConVar g_cWebhook = null;
ConVar g_cColor = null;
ConVar g_cAvatar = null;
ConVar g_cUsername = null;

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
    g_cWebhook = AutoExecConfig_CreateConVar("sun_discor_webhook_url", "", "Your webhook url. Don't forget to add \"/slack\" at the end.");
    g_cColor = AutoExecConfig_CreateConVar("sun_discord_color", "#FF69B4", "Hexcode of the color (with '#' !)");
    g_cAvatar = AutoExecConfig_CreateConVar("sun_discord_avatar", "https://bara.dev/images/sun.png", "URL to Avatar image");
    g_cUsername = AutoExecConfig_CreateConVar("sun_discord_username", "Simple Update Notifier", "Discord username");
    AutoExecConfig_ExecuteFile();
    AutoExecConfig_CleanFile();
}

public void SUN_OnUpdate(int iLocalVersion, int iSteamVersion)
{
    char sHostname[512];
    ConVar cHostname = FindConVar("hostname");

    if (cHostname == null)
    {
        return;
    }

    cHostname.GetString(sHostname, sizeof(sHostname));
    
    char sName[128];
    g_cUsername.GetString(sName, sizeof(sName));

    char sHook[128];
    g_cWebhook.GetString(sHook, sizeof(sHook));

    DiscordWebHook hook = new DiscordWebHook(sHook);
    hook.SlackMode = true;
    hook.SetUsername(sName);

    char sColor[12], sAvatar[512];
    g_cColor.GetString(sColor, sizeof(sColor));
    g_cAvatar.GetString(sAvatar, sizeof(sAvatar));

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
