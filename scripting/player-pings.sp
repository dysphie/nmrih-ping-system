#include <sourcemod>
#include <sdktools>
#include <morecolors>

#undef REQUIRE_EXTENSIONS
#include <clientprefs>
#define REQUIRE_EXTENSIONS

#pragma semicolon 1
#pragma newdecls required

#define NMR_MAXPLAYERS	   9
#define IN_VOICECMD		   0x80000000
#define MATH_PI			   3.141592653
#define ADMFLAG_PING	   ADMFLAG_GENERIC

#define MAX_PINGS		   25

#define R				   0
#define G				   1
#define B				   2
#define A				   3

#define PLUGIN_DESCRIPTION "Allows players to highlight entities and place markers in the world"
#define PLUGIN_VERSION	   "1.0.6"

public Plugin myinfo =
{
	name		= "Player Pings",
	author		= "Dysphie",
	description = PLUGIN_DESCRIPTION,
	version		= PLUGIN_VERSION,
	url			= "https://github.com/dysphie/nmrih-ping-system"
};

// point_message flags
enum
{
    POINT_MESSAGE_DEVELOPER_ONLY = 1 << 0,
    POINT_MESSAGE_FONT_PROPORTIONAL = 1 << 1,
    POINT_MESSAGE_FONT_DROP_SHADOW = 1 << 2,
    POINT_MESSAGE_OFFSET_POSITION = 1 << 3,
};

enum Unit
{
	Unit_Default = -1,
	Unit_Meters,
	Unit_Feet,
	Unit_Hammer,
	Unit_MAX
}

bool   g_ClientPrefs;

ConVar cvEnabled;
ConVar cvLifetime;
ConVar cvColorR;
ConVar cvColorG;
ConVar cvColorB;
ConVar cvRange;
ConVar cvIcon;
ConVar cvIconOffset;
ConVar cvBucketSize;
ConVar cvTokensPerSecond;
ConVar cvSound;
ConVar cvShowDistance;
ConVar cvShowDistanceInterval;
ConVar cvDistanceUnits;
ConVar cvAllowNPCs;
ConVar cvAllowPlayers;
ConVar cvRandomizeColor;
ConVar cvCircleSegments;
ConVar cvCircleRadius;
ConVar cvAllowDead;
ConVar cvTextLocation;
ConVar cvGlobalCooldown;
ConVar cvLimit;
ConVar cvAdminImmunity;

int	   g_LaserIndex;
int	   g_HaloIndex;

Cookie optOutCookie;
Cookie unitsCookie;

float  g_Tokens[NMR_MAXPLAYERS + 1];
float  g_LastUpdate[NMR_MAXPLAYERS + 1];
int	   g_PingColor[NMR_MAXPLAYERS + 1][3];
float  g_PingExpireTime[MAX_PINGS];

public void OnAllPluginsLoaded()
{
	g_ClientPrefs = LibraryExists("clientprefs");
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "clientprefs"))
	{
		g_ClientPrefs = false;
	}
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "clientprefs"))
	{
		OnClientPrefsLoaded();
	}
}

void OnClientPrefsLoaded()
{
	g_ClientPrefs = true;
	optOutCookie = new Cookie("disable_player_pings", "Toggles seeing player pings", CookieAccess_Private);
	unitsCookie	 = new Cookie("player_ping_units", "Distance units to use for player pings", CookieAccess_Private);
	SetCookieMenuItem(CustomCookieMenu, 0, "Player Pings");
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	MarkNativeAsOptional("Cookie.Cookie");
	MarkNativeAsOptional("Cookie.Get");
	MarkNativeAsOptional("Cookie.GetInt");
	MarkNativeAsOptional("Cookie.Set");
	MarkNativeAsOptional("Cookie.SetInt");
	MarkNativeAsOptional("SetCookieMenuItem");
	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("player-pings.phrases");

	cvEnabled			   = CreateConVar("sm_ping_enabled", "1", "Whether player pings are enabled");
	cvTokensPerSecond	   = CreateConVar("sm_ping_cooldown_tokens_per_second", "0.00833", "Tokens added to the bucket per second");
	cvBucketSize		   = CreateConVar("sm_ping_cooldown_bucket_size", "2", "Number of command tokens that fit in the cooldown bucket");
	cvGlobalCooldown	   = CreateConVar("sm_ping_cooldown_shared", "0", "Whether the ping cooldown applies to all players or each player separately");
	cvAdminImmunity		   = CreateConVar("sm_ping_cooldown_admin_immunity", "1", "Whether admins are immune to ping cooldowns");
	cvIconOffset		   = CreateConVar("sm_ping_text_height_offset", "30.0", "Vertically offsets the ping caption from its target position by a specified amount, in game units");
	cvColorR			   = CreateConVar("sm_ping_color_r", "10", "The red color component for player pings");
	cvColorG			   = CreateConVar("sm_ping_color_g", "224", "The green color component for player pings");
	cvColorB			   = CreateConVar("sm_ping_color_b", "247", "The blue color component for player pings");
	cvShowDistance		   = CreateConVar("sm_ping_distance_show", "1", "If true, shows distance to the ping location in the caption");
	cvShowDistanceInterval = CreateConVar("sm_ping_distance_update_interval", "0.3", "How often distance is updated in the ping caption");
	cvDistanceUnits		   = CreateConVar("sm_ping_distance_default_units", "0", "Default distance units for players without preference. 0 = Meters, 1 = Feet, 2 = Hammer units", _,
										  true, 0.0, true, (float)(view_as<int>(Unit_MAX) - 1));
	cvRandomizeColor	   = CreateConVar("sm_ping_color_randomize", "1", "If true, randomize the ping color for each player instead of using RGB variables");
	cvLifetime			   = CreateConVar("sm_ping_lifetime", "8", "The lifetime of player pings in seconds", _, true, 1.0);
	cvRange				   = CreateConVar("sm_ping_range", "3000", "The maximum reach of the player ping trace in game units");
	cvIcon				   = CreateConVar("sm_ping_icon", "icon_interact", "The icon used for player pings. Empty to disable");
	cvSound				   = CreateConVar("sm_ping_sound", "ui/hint.wav", "The sound used for player pings");
	cvCircleRadius		   = CreateConVar("sm_ping_circle_radius", "9.0", "Radius of the ping circle");
	cvCircleSegments	   = CreateConVar("sm_ping_circle_segments", "10", "How many straight lines make up the ping circle");
	cvAllowPlayers		   = CreateConVar("sm_ping_players", "0", "Whether pings can target other players");
	cvAllowNPCs			   = CreateConVar("sm_ping_npcs", "0", "Whether pings can target zombies");
	cvAllowDead			   = CreateConVar("sm_ping_dead_can_use", "1", "Whether dead players can ping");
	cvTextLocation		   = CreateConVar("sm_ping_text_location", "0", "Where to place the ping text. 0 = On screen, 1 = In the world");
	cvLimit				   = CreateConVar("sm_ping_limit", "3", "The maximum number of pings that can be active at once", _, true, 1.0, true, (float)(MAX_PINGS));

	CreateConVar("player_pings_version", PLUGIN_VERSION, PLUGIN_DESCRIPTION,
				 FCVAR_SPONLY | FCVAR_NOTIFY | FCVAR_DONTRECORD);

	cvSound.AddChangeHook(OnPingSoundConVarChanged);

	AutoExecConfig(true, "player-pings");
	RegConsoleCmd("sm_ping", Cmd_Ping, "Place a marker on the location you are pointing at");

	if (LibraryExists("clientprefs"))
	{
		OnClientPrefsLoaded();
	}

	SupportLateload();
}

void SupportLateload()
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientConnected(client))
		{
			OnClientConnected(client);
		}
	}
}

void CustomCookieMenu(int client, CookieMenuAction action, any info, char[] buffer, int maxlen)
{
	CookiesMenu(client);
}

void CookiesMenu(int client)
{
	Menu menu = new Menu(MenuHandler_CookiesMenu, MenuAction_DisplayItem);

	char buffer[255];
	FormatEx(buffer, sizeof(buffer), "%T", "Ping Settings Title", client);
	menu.SetTitle(buffer);

	FormatEx(buffer, sizeof(buffer), "%T: %T", "Setting: Toggle", client,
			 HasPingsEnabled(client) ? "Cookie Enabled" : "Cookie Disabled", client);

	menu.AddItem("toggle", buffer);

	Unit unit = GetClientUnits(client);

	char unitPhrase[32];
	GetUnitsPhraseLong(unit, unitPhrase, sizeof(unitPhrase));

	FormatEx(buffer, sizeof(buffer), "%T: %T", "Setting: Units", client, unitPhrase, client);

	menu.AddItem("units", buffer);

	menu.Display(client, MENU_TIME_FOREVER);
}

int MenuHandler_CookiesMenu(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		delete menu;
		return 0;
	}

	if (action == MenuAction_Select)
	{
		int	 client	   = param1;
		int	 selection = param2;

		char info[32], display[255];
		menu.GetItem(selection, info, sizeof(info), _, display, sizeof(display));

		if (StrEqual(info, "toggle"))
		{
			bool optedOut = _CookieGetInt(optOutCookie, client) != 0;
			_CookieSetInt(optOutCookie, client, !optedOut);
		}

		else if (StrEqual(info, "units"))
		{
			Unit unit = GetClientUnits(client);
			unit++;

			if (unit >= Unit_MAX)
			{
				unit = Unit_Meters;
			}

			SetClientUnits(client, unit);
		}

		// Redraw the menu
		CookiesMenu(client);
	}

	return 0;
}

void OnPingSoundConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (newValue[0])
	{
		PrecacheSound(newValue);
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if ((buttons & IN_VOICECMD) && (buttons & IN_USE) && cvEnabled.BoolValue)
	{
		int oldButtons = GetEntProp(client, Prop_Data, "m_nOldButtons");
		if (!(oldButtons & IN_USE) && CheckCanUsePing(client))
		{
			DoPing(client, cvLifetime.IntValue);
		}
	}

	return Plugin_Continue;
}

Action Cmd_Ping(int client, int args)
{
	if (!client)
	{
		CReplyToCommand(client, "In-game command only.");
		return Plugin_Handled;
	}

	if (!cvEnabled.BoolValue)
	{
		CReplyToCommand(client, "%t", "Ping Disabled");
		return Plugin_Handled;
	}

	if (!IsPlayerAlive(client) && !cvAllowDead.BoolValue)
	{
		CReplyToCommand(client, "%t", "Must Be Alive");
		return Plugin_Handled;
	}

	int duration = cvLifetime.IntValue;

	if (args > 0 && CheckCommandAccess(client, "ping_custom_duration", ADMFLAG_PING))
	{
		int customDuration = GetCmdArgInt(1);
		if (customDuration > 0)
		{
			duration = customDuration;
		}
	}

	if (CheckCanUsePing(client))
	{
		DoPing(client, duration);
	}

	return Plugin_Handled;
}

void DoPing(int client, int duration)
{
	float eyeAng[3], eyePos[3];
	GetClientEyeAngles(client, eyeAng);
	GetClientEyePosition(client, eyePos);

	// Start with an accurate trace ray
	Handle rayTrace = TR_TraceRayFilterEx(eyePos, eyeAng, MASK_VISIBLE, RayType_Infinite, TraceFilter_Ping, client);
	int	   rayEnt	= TR_GetEntityIndex(rayTrace);

	// Check if we hit an entity with the ray
	if (IsValidEdict(rayEnt) && CouldEntityGlow(rayEnt))
	{
		float endPos[3];
		TR_GetEndPosition(endPos, rayTrace);

		PingEntity(rayEnt, client, duration);

		delete rayTrace;
		return;
	}

	// If we hit nothing, try again using a swept hull

	float hullStart[3];
	ForwardVector(eyePos, eyeAng, 32.0, hullStart);

	float hullEnd[3];
	ForwardVector(eyePos, eyeAng, cvRange.FloatValue, hullEnd);

	float traceWidth = 16.0;

	float hullMins[3];
	hullMins[0] = -traceWidth;
	hullMins[1] = -traceWidth;
	hullMins[2] = -traceWidth;

	float hullMaxs[3];
	hullMaxs[0]		 = traceWidth;
	hullMaxs[1]		 = traceWidth;
	hullMaxs[2]		 = traceWidth;

	Handle hullTrace = TR_TraceHullFilterEx(hullStart, hullEnd, hullMins, hullMaxs, MASK_VISIBLE, TraceFilter_Ping, client);

	int	   hullEnt	 = TR_GetEntityIndex(hullTrace);

	if (!IsValidEntity(hullEnt) || !CouldEntityGlow(hullEnt))
	{
		// If we didn't hit anything glowable with the hull, prefer ray trace and ping the world
		float endPos[3];
		TR_GetEndPosition(endPos, rayTrace);

		float normal[3];
		TR_GetPlaneNormal(rayTrace, normal);

		PingWorld(endPos, normal, client, duration);
	}
	else
	{
		PingEntity(hullEnt, client, duration);
	}

	delete hullTrace;
	delete rayTrace;
}

bool CouldEntityGlow(int entity)
{
	char classname[32];
	GetEntityClassname(entity, classname, sizeof(classname));

	return IsValidEdict(entity) && HasEntProp(entity, Prop_Send, "m_bGlowing") && HasEntProp(entity, Prop_Data, "m_bIsGlowable") && HasEntProp(entity, Prop_Data, "m_clrGlowColor") && HasEntProp(entity, Prop_Data, "m_flGlowDistance");
}

void PingWorld(float pos[3], float normal[3], int issuer, int duration)
{
	if (cvTextLocation.IntValue == 0)
	{
		// Create something for our instructor to latch onto
		int entity = CreateEntityByName("info_target_instructor_hint");
		TeleportEntity(entity, pos);
		DispatchSpawn(entity);

		// Give it time to network
		DataPack data;
		CreateDataTimer(0.1, Frame_BeginDrawInstructorAll, data, TIMER_FLAG_NO_MAPCHANGE);
		data.WriteCell(EntIndexToEntRef(entity));
		data.WriteCell(GetClientSerial(issuer));
		data.WriteCell(duration);

		// Delete helper entity after ping has expired
		CreateTimer(float(duration) + 0.1, Timer_DeleteHelperEntity, EntIndexToEntRef(entity));
	}
	else
	{
		BeginDrawWorldTextAll(pos, issuer, duration);
	}

	// Now draw beam circle where we hit
	DrawCircleOnSurface(pos, cvCircleRadius.FloatValue, cvCircleSegments.IntValue, normal, duration, g_PingColor[issuer]);

	EmitPingSoundToAll();
	SaveActivePing(duration);
}

void EmitPingSoundToAll()
{
	char hintSound[PLATFORM_MAX_PATH];
	cvSound.GetString(hintSound, sizeof(hintSound));
	if (!hintSound[0])
	{
		return;
	}

	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && HasPingsEnabled(client))
		{
			EmitSoundToClient(client, hintSound, SOUND_FROM_PLAYER);
		}
	}
}

Action Timer_DeleteWorldText(Handle timer, int pingID)
{
	RemoveWorldTextAll(pingID);
	return Plugin_Continue;
}

void RemoveWorldTextAll(int pingID)
{
	Handle	msg = StartMessageAll("RemovePointMessage", USERMSG_RELIABLE | USERMSG_BLOCKHOOKS);
	BfWrite bf	= UserMessageToBfWrite(msg);
	bf.WriteShort(pingID);
	EndMessage();
}

void BeginDrawWorldTextAll(float pos[3], int issuer, int duration, int moveParent = -1)
{
	static int pingID		= 5000;	   // Start high so we don't override map texts

	bool	   showDistance = cvShowDistance.BoolValue;

	char	   issuerName[MAX_NAME_LENGTH];
	GetClientName(issuer, issuerName, sizeof(issuerName));

	DrawWorldTextAll(pingID, pos, g_PingColor[issuer], issuerName, showDistance, moveParent);

	if (!showDistance)
	{
		// If we don't display distance we just need one single use timer
		CreateTimer(cvLifetime.FloatValue, Timer_DeleteWorldText, pingID);
	}
	else
	{
		// Otherwise we constantly update the thing
		DataPack data;
		CreateDataTimer(cvShowDistanceInterval.FloatValue, Timer_UpdateWorldTextAll, data, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);	
		data.WriteCell(pingID);
		data.WriteCell(moveParent != -1 ? EntIndexToEntRef(moveParent) : -1);
		data.WriteFloat(GetGameTime() + (float)(duration));
		data.WriteFloatArray(pos, sizeof(pos));
		data.WriteCellArray(g_PingColor[issuer], sizeof(g_PingColor[]));
		data.WriteString(issuerName);
	}

	pingID++;
}

void DrawWorldTextAll(int pingID, float pos[3], int color[3], const char[] issuerName, bool showDistance = false, int moveParent = -1)
{
	float adjustedPos[3];
	adjustedPos[0] = pos[0];
	adjustedPos[1] = pos[1];
	adjustedPos[2] = pos[2] + cvIconOffset.FloatValue;

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || !HasPingsEnabled(client))
		{
			continue;
		}

		SetGlobalTransTarget(client);

		char caption[255];
		FormatCaptionForClient(issuerName, pos, showDistance, client, caption, sizeof(caption));

		Handle	msg = StartMessageOne("PointMessage", client, USERMSG_BLOCKHOOKS);
		BfWrite bf	= UserMessageToBfWrite(msg);
		bf.WriteString(caption);
		bf.WriteShort(pingID);
		bf.WriteShort(/*POINT_MESSAGE_FONT_PROPORTIONAL| */POINT_MESSAGE_FONT_DROP_SHADOW);	 // flags
		bf.WriteVecCoord(adjustedPos);
		bf.WriteFloat(cvRange.FloatValue);	  // radius
		bf.WriteString("PointMessageDefault");
		bf.WriteByte(color[R]);	   // r
		bf.WriteByte(color[G]);	   // g
		bf.WriteByte(color[B]);	   // b
		bf.WriteShort(moveParent);
		bf.WriteFloat(0.5); // Height offset
		EndMessage();
	}
}

void FormatCaptionForClient(const char[] issuerName, float pos[3], bool showDistance, int client, char[] buffer, int maxlen)
{
	if (showDistance)
	{
		float clientPos[3];
		GetClientAbsOrigin(client, clientPos);

		float distance = GetVectorDistance(pos, clientPos);

		Unit  units	   = GetClientUnits(client);
		distance *= GetUnitMultiplier(units);

		char unitsPhrase[32];
		GetUnitsPhrase(units, unitsPhrase, sizeof(unitsPhrase));

		Format(buffer, maxlen, "%T", "Caption With Distance", client, issuerName, distance, unitsPhrase, client);
	}
	else
	{
		Format(buffer, maxlen, "%T", "Caption", client, issuerName);
	}
}

void GetUnitsPhrase(Unit unit, char[] buffer, int maxlen)
{
	char phrases[][] = {
		"Meters, Short",
		"Feet, Short",
		"Hammer Units, Short"
	};

	strcopy(buffer, maxlen, phrases[unit]);
}

void GetUnitsPhraseLong(Unit unit, char[] buffer, int maxlen)
{
	char phrases[][] = {
		"Meters, Long",
		"Feet, Long",
		"Hammer Units, Long"
	};

	strcopy(buffer, maxlen, phrases[unit]);
}

Action Timer_UpdateWorldTextAll(Handle timer, DataPack data)
{
	data.Reset();

	int pingID  = data.ReadCell();

	int moveParent = -1;
	int moveParentRef = data.ReadCell();
	if (moveParentRef != INVALID_ENT_REFERENCE) 
	{ 
		moveParent = EntRefToEntIndex(moveParentRef);
		if (moveParent == -1) 
		{
			RemoveWorldTextAll(pingID);
			return Plugin_Stop;
		}
	}

	float endTime = data.ReadFloat();

	if (GetGameTime() >= endTime)
	{
		RemoveWorldTextAll(pingID);
		return Plugin_Stop;
	}

	float pos[3];
	data.ReadFloatArray(pos, sizeof(pos));

	int color[3];
	data.ReadCellArray(color, sizeof(color));

	char issuerName[MAX_NAME_LENGTH];
	data.ReadString(issuerName, sizeof(issuerName));

	
	DrawWorldTextAll(pingID, pos, color, issuerName, true, moveParent);
	return Plugin_Continue;
}

void PingEntity(int entity, int issuer, int duration)
{
	HighlightEntity(entity, duration, g_PingColor[issuer]);

	if (cvTextLocation.IntValue == 0)
	{
		BeginDrawInstructorAll(entity, issuer, duration);
	}
	else
	{
		float pos[3];
		GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", pos);
		BeginDrawWorldTextAll(pos, issuer, duration, entity);
	}

	EmitPingSoundToAll();
	SaveActivePing(duration);
}

Action Frame_BeginDrawInstructorAll(Handle timer, DataPack data)
{
	data.Reset();
	int entity	 = EntRefToEntIndex(data.ReadCell());
	int issuer	 = GetClientFromSerial(data.ReadCell());
	int duration = data.ReadCell();

	if (!issuer || !IsClientInGame(issuer) || !IsValidEntity(entity))
	{
		return Plugin_Stop;
	}

	BeginDrawInstructorAll(entity, issuer, duration);
	return Plugin_Stop;
}

void BeginDrawInstructorAll(int entity, int issuer, int duration)
{
	float pos[3];
	GetEntityAbsOrigin(entity, pos);

	bool showDistance = cvShowDistance.BoolValue;

	char issuerName[MAX_NAME_LENGTH];
	GetClientName(issuer, issuerName, sizeof(issuerName));

	DrawInstructorToAll(entity, pos, g_PingColor[issuer], issuerName, duration, showDistance);

	if (!showDistance)
	{
		return;
	}

	DataPack data;
	CreateDataTimer(cvShowDistanceInterval.FloatValue, Timer_UpdateInstructorAll, data, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	data.WriteFloat(GetGameTime() + (float)(duration));
	data.WriteCell(EntIndexToEntRef(entity));
	data.WriteFloatArray(pos, sizeof(pos));
	data.WriteCellArray(g_PingColor[issuer], sizeof(g_PingColor[]));
	data.WriteString(issuerName);
	data.WriteCell(showDistance);
}

Action Timer_UpdateInstructorAll(Handle timer, DataPack data)
{
	data.Reset();

	float endTime = data.ReadFloat();
	int	  entity  = EntRefToEntIndex(data.ReadCell());

	if (GetGameTime() >= endTime || !IsValidEntity(entity))
	{
		return Plugin_Stop;
	}

	float pos[3];
	data.ReadFloatArray(pos, sizeof(pos));
	// If in the player's inventory, the location of the entity is fixed to where it was when it was picked up.
	// Todo: What should be obtained is the player's position
	if( IsValidEntity(entity) )
	{
		GetEntityAbsOrigin(entity, pos);
	}

	int color[3];
	data.ReadCellArray(color, sizeof(color));

	char issuerName[MAX_NAME_LENGTH];
	data.ReadString(issuerName, sizeof(issuerName));

	bool showDistance = data.ReadCell();

	DrawInstructorToAll(entity, pos, color, issuerName, cvShowDistanceInterval.IntValue + 1, showDistance);
	return Plugin_Continue;
}

// void RemoveInstructorAll(int client, const char[] hintName)
// {
//     Event event = CreateEvent("instructor_server_hint_stop", true);
//     event.SetString("hint_name", hintName);
//     event.FireToClient(client);
//     event.Close();
// }

void GetEntityAbsOrigin(int entity, float pos[3])
{
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", pos);
}

Action Timer_DeleteHelperEntity(Handle timer, int entRef)
{
	if (IsValidEntity(entRef))
	{
		RemoveEntity(entRef);
	}

	return Plugin_Continue;
}

void HighlightEntity(int entity, int duration, int color[3])
{
	// Don't glow if we are already glowing
	// TODO: Handle this more nicely, extend the duration?
	if (GetEntProp(entity, Prop_Send, "m_bGlowing") != 0)
	{
		return;
	}

	char classname[80];
	GetEntityClassname(entity, classname, sizeof(classname));

	char rgb[40];
	FormatEx(rgb, sizeof(rgb), "%d %d %d", color[R], color[G], color[B]);

	int	  oldGlowColor = GetEntProp(entity, Prop_Send, "m_clrGlowColor");
	float oldGlowDist  = GetEntPropFloat(entity, Prop_Send, "m_flGlowDistance");

	// TODO: Why don't we use above dataprops for these?
	DispatchKeyValue(entity, "glowable", "1");
	DispatchKeyValue(entity, "glowdistance", "-1");
	DispatchKeyValue(entity, "glowcolor", rgb);
	AcceptEntityInput(entity, "EnableGlow", entity, entity);

	DataPack data;
	CreateDataTimer((float)(duration), Timer_UnhighlightEntity, data, TIMER_FLAG_NO_MAPCHANGE);
	data.WriteCell(EntIndexToEntRef(entity));
	data.WriteCell(oldGlowColor);
	data.WriteFloat(oldGlowDist);
}

Action Timer_UnhighlightEntity(Handle timer, DataPack data)
{
	data.Reset();
	int entity = EntRefToEntIndex(data.ReadCell());
	if (entity != -1)
	{
		SetEntProp(entity, Prop_Send, "m_clrGlowColor", data.ReadCell());
		SetEntPropFloat(entity, Prop_Send, "m_flGlowDistance", data.ReadFloat());

		AcceptEntityInput(entity, "DisableGlow", entity, entity);
	}

	return Plugin_Continue;
}

public bool TraceFilter_Ping(int entity, int contentMask, int ignore)
{
	if (!cvAllowPlayers.BoolValue && 0 < entity <= MaxClients)
	{
		return false;
	}

	if (!cvAllowNPCs.BoolValue)
	{
		char classname[11];
		GetEntityClassname(entity, classname, sizeof(classname));
		return !StrEqual(classname, "npc_nmrih_");
	}

	return entity != ignore;
}

void ForwardVector(const float vPos[3], const float vAng[3], float fDistance, float vReturn[3])
{
	float vDir[3];
	GetAngleVectors(vAng, vDir, NULL_VECTOR, NULL_VECTOR);
	vReturn = vPos;
	vReturn[0] += vDir[0] * fDistance;
	vReturn[1] += vDir[1] * fDistance;
	vReturn[2] += vDir[2] * fDistance;
}

void DrawInstructorToAll(int entity, float pos[3], int color[3], const char[] issuerName, int duration, bool showDistance = false)
{
	duration = max(duration, 1);	// never infinite

	char colorStr[40];
	FormatEx(colorStr, sizeof(colorStr), "%d,%d,%d", color[R], color[G], color[B]);

	char icon[32];
	cvIcon.GetString(icon, sizeof(icon));

	char hintKey[32];
	FormatEx(hintKey, sizeof(hintKey), "👆%d", entity);

	char hintSound[PLATFORM_MAX_PATH];
	cvSound.GetString(hintSound, sizeof(hintSound));

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || !HasPingsEnabled(client))
		{
			continue;
		}

		char caption[255];
		FormatCaptionForClient(issuerName, pos, showDistance, client, caption, sizeof(caption));

		Event event = CreateEvent("instructor_server_hint_create", true);
		event.SetString("hint_caption", caption);
		event.SetString("hint_activator_caption", caption);
		event.SetString("hint_name", hintKey);
		event.SetString("hint_replace_key", hintKey);
		event.SetInt("hint_target", entity);
		event.SetInt("hint_activator_userid", GetClientUserId(client));
		event.SetInt("hint_timeout", duration);
		event.SetString("hint_icon_onscreen", icon);
		event.SetString("hint_icon_offscreen", icon);
		event.SetString("hint_color", colorStr);
		event.SetFloat("hint_icon_offset", cvIconOffset.FloatValue);
		event.SetFloat("hint_range", cvRange.FloatValue);
		event.SetInt("hint_flags", 0);
		event.SetString("hint_binding", "");
		event.SetBool("hint_allow_nodraw_target", true);
		event.SetBool("hint_nooffscreen", icon[0] == '\0');
		event.SetBool("hint_forcecaption", true);
		event.SetBool("hint_local_player_only", false);
		event.SetString("hint_start_sound", "common/null.wav");	   // We will play our own which isn't buggy
		event.SetInt("hint_target_pos", 2);						   // World center
		event.FireToClient(client);
		event.Cancel();
	}
}

void TE_SendBeam(const float start[3], const float end[3], int duration, int rgb[3])
{
	int rgba[4];
	rgba	= rgb;
	rgba[A] = 255;

	TE_SetupBeamPoints(start, end, g_LaserIndex, g_HaloIndex,
					   .StartFrame = 0,
					   .FrameRate  = 0,
					   .Life	   = (float)(duration),
					   .Width	   = 0.5,
					   .EndWidth   = 0.5,
					   .FadeLength = 1,
					   .Amplitude  = 0.0,
					   .Color	   = rgba,
					   .Speed	   = 0);

	int recipients[NMR_MAXPLAYERS];
	int numRecipients = 0;

	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && HasPingsEnabled(client))
		{
			recipients[numRecipients++] = client;
		}
	}

	TE_Send(recipients, numRecipients);
}

public void OnMapStart()
{
	for (int i = 0; i < sizeof(g_PingExpireTime); i++)
	{
		g_PingExpireTime[i] = 0.0;
	}

	g_Tokens[0]		= cvBucketSize.FloatValue;
	g_LastUpdate[0] = 0.0;

	g_LaserIndex	= PrecacheModel("materials/sprites/laserbeam.vmt");
	g_HaloIndex		= PrecacheModel("materials/sprites/halo01.vmt");

	PrecacheSound("common/null.wav");

	char hintSound[PLATFORM_MAX_PATH];
	cvSound.GetString(hintSound, sizeof(hintSound));
	if (hintSound[0])
	{
		PrecacheSound(hintSound);
	}
}

void DrawCircleOnSurface(float center[3], float radius, int segments, float normal[3], int duration, int color[3])
{
	duration = min(duration, 25);	 // TODO: Beams can't last longer than 25 seconds, use a timer?

	float prevPoint[3], currPoint[3];
	float tangent1[3], tangent2[3];

	// Precompute constant values
	float angleStep = 2.0 * MATH_PI / segments;

	ComputeTangents(normal, tangent1, tangent2);

	// Inline the normalization calculation directly into the code
	NormalizeVector(tangent1, tangent1);
	NormalizeVector(tangent2, tangent2);

	for (int i = 0; i <= segments; i++)
	{
		float angle	   = angleStep * i;
		float cosAngle = Cosine(angle);
		float sinAngle = Sine(angle);

		currPoint[0]   = center[0] - (-1.0 * normal[0]) + (radius * cosAngle * tangent1[0]) + (radius * sinAngle * tangent2[0]);
		currPoint[1]   = center[1] - (-1.0 * normal[1]) + (radius * cosAngle * tangent1[1]) + (radius * sinAngle * tangent2[1]);
		currPoint[2]   = center[2] - (-1.0 * normal[2]) + (radius * cosAngle * tangent1[2]) + (radius * sinAngle * tangent2[2]);

		if (prevPoint[0] != 0.0 && prevPoint[1] != 0.0 && prevPoint[2] != 0.0)
		{
			TE_SendBeam(prevPoint, currPoint, duration, color);
		}

		prevPoint[0] = currPoint[0];
		prevPoint[1] = currPoint[1];
		prevPoint[2] = currPoint[2];
	}
}

void ComputeTangents(const float normal[3], float tangent1[3], float tangent2[3])
{
	if (normal[0] != 0 || normal[1] != 0)
	{
		tangent1[0] = -normal[1];
		tangent1[1] = normal[0];
		tangent1[2] = 0.0;
	}
	else {
		tangent1[0] = 1.0;
		tangent1[1] = 0.0;
		tangent1[2] = 0.0;
	}

	GetVectorCrossProduct(normal, tangent1, tangent2);
}

bool CheckCanUsePing(int client)
{
	if (cvAdminImmunity.BoolValue && CheckCommandAccess(client, "ping_cooldown_immunity", ADMFLAG_PING))
	{
		return true;
	}

	if (!HasPingsEnabled(client))
	{
		return false;
	}

	if (GetActivePings() >= cvLimit.IntValue)
	{
		CPrintToChat(client, "%t", "Too Many Pings");
		return false;
	}

	int	  cooldownIndex			= cvGlobalCooldown.BoolValue ? 0 : client;

	float currentTime			= GetGameTime();
	float time_elapsed			= currentTime - g_LastUpdate[cooldownIndex];
	float tokensToAdd			= time_elapsed * cvTokensPerSecond.FloatValue;
	g_Tokens[cooldownIndex]		= min(g_Tokens[cooldownIndex] + tokensToAdd, cvBucketSize.FloatValue);
	g_LastUpdate[cooldownIndex] = currentTime;

	if (g_Tokens[cooldownIndex] >= 1.0)
	{
		g_Tokens[cooldownIndex] -= 1.0;
		return true;
	}

	// We are on cooldown, calculate remaining seconds
	float secondsLeft = (1.0 - g_Tokens[cooldownIndex]) / cvTokensPerSecond.FloatValue;
	CPrintToChat(client, "%t", "On Cooldown", RoundToCeil(secondsLeft));
	return false;
}

any min(any x, any y)
{
	return (x < y) ? x : y;
}

any max(any x, any y)
{
	return (x > y) ? x : y;
}

bool HasPingsEnabled(int client)
{
	return !g_ClientPrefs || _CookieGetInt(optOutCookie, client) == 0;
}

public void OnClientConnected(int client)
{
	g_Tokens[client] = cvBucketSize.FloatValue;
	g_LastUpdate[client] = 0.0;
	ComputePingColor(client);
}

void ComputePingColor(int client)
{
	if (cvRandomizeColor.BoolValue)
	{
		RandomReadableColor(g_PingColor[client]);
	}
	else
	{
		g_PingColor[client][R] = cvColorR.IntValue;
		g_PingColor[client][G] = cvColorG.IntValue;
		g_PingColor[client][B] = cvColorB.IntValue;
	}
}

void RandomReadableColor(int rgb[3])
{
	float h = GetRandomFloat(0.0, 360.0);
	float s = 1.0;
	float l = 0.5;

	// Avoid less readable blue-violet range
	if (h >= 212.0 && h <= 283.0)
	{
		if (h < 246.0)
		{
			h -= 71.0;
		}
		else {
			h += 71.0;
		}
	}

	HSLToRGB(h, s, l, rgb[R], rgb[G], rgb[B]);
}

float HueToRGB(float v1, float v2, float vH)
{
	if (vH < 0)
		vH += 1;

	if (vH > 1)
		vH -= 1;

	if ((6 * vH) < 1)
		return (v1 + (v2 - v1) * 6 * vH);

	if ((2 * vH) < 1)
		return v2;

	if ((3 * vH) < 2)
		return (v1 + (v2 - v1) * ((2.0 / 3) - vH) * 6);

	return v1;
}

void HSLToRGB(float h, float s, float l, int &r, int &g, int &b)
{
	if (s == 0)
	{
		r = g = b = RoundToFloor(l * 255);
	}
	else
	{
		float v1, v2;
		float hue = h / 360.0;

		v2		  = (l < 0.5) ? (l * (1 + s)) : ((l + s) - (l * s));
		v1		  = 2 * l - v2;

		r		  = RoundToFloor(255 * HueToRGB(v1, v2, hue + (1.0 / 3)));
		g		  = RoundToFloor(255 * HueToRGB(v1, v2, hue));
		b		  = RoundToFloor(255 * HueToRGB(v1, v2, hue - (1.0 / 3)));
	}
}

Unit GetClientUnits(int client)
{
	if (!g_ClientPrefs)
	{
		return view_as<Unit>(cvDistanceUnits.IntValue);
	}

	Unit cookieVal = view_as<Unit>(_CookieGetInt(unitsCookie, client) - 1);
	if (cookieVal <= Unit_Default || cookieVal >= Unit_MAX)
	{
		cookieVal = view_as<Unit>(cvDistanceUnits.IntValue);
	}
	return cookieVal;
}

void SetClientUnits(int client, Unit units)
{
	_CookieSetInt(unitsCookie, client, view_as<int>(units) + 1);
}

// Backport Cookie.SetInt/GetInt methods from 1.12
void _CookieSetInt(Cookie cookie, int client, int value)
{
	char str[12];
	IntToString(value, str, sizeof(str));
	cookie.Set(client, str);
}

int _CookieGetInt(Cookie cookie, int client)
{
	char value[12];
	cookie.Get(client, value, sizeof(value));
	return StringToInt(value);
}

float GetUnitMultiplier(Unit units)
{
	switch (units)
	{
		case Unit_Meters:
		{
			return 0.01905;
		}
		case Unit_Feet:
		{
			return 0.08333232;
		}
		default:
		{
			return 1.0;
		}
	}
}

bool SaveActivePing(int duration = -1)
{
	int maxPings = min(cvLimit.IntValue, sizeof(g_PingExpireTime));
	if (maxPings <= 0)
	{
		return false;
	}

	float curTime = GetGameTime();

	for (int i = 0; i < maxPings; i++)
	{
		float expireTime = g_PingExpireTime[i];

		// Find an expired ping cell to place our new ping
		if (curTime >= expireTime)
		{
			g_PingExpireTime[i] = curTime + (float)(duration);
			return true;
		}
	}

	return false;
}

int GetActivePings()
{
	int maxPings = min(cvLimit.IntValue, sizeof(g_PingExpireTime));
	if (maxPings <= 0)
	{
		return false;
	}

	int	  count	  = 0;

	float curTime = GetGameTime();

	for (int i = 0; i < maxPings; i++)
	{
		if (g_PingExpireTime[i] > curTime)
		{
			count++;
		}
	}

	return count;
}
