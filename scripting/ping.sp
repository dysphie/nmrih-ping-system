#include <sourcemod>
#include <sdktools>
#include <morecolors>

#undef REQUIRE_PLUGIN
#include <clientprefs>
//#include <debugoverlays>
#define REQUIRE_PLUGIN

#pragma semicolon 1
#pragma newdecls required

#pragma semicolon 1
#pragma newdecls required

#define NMR_MAXPLAYERS 9
#define IN_VOICECMD	   0x80000000
#define MATH_PI		   3.141592653
#define ADMFLAG_PING   ADMFLAG_GENERIC
// #define MULTIPLIER_METERS 0.01905
// #define MULTIPLIER_FEET	  0.08333232

public Plugin myinfo =
{
	name		= "Player Pings",
	author		= "Dysphie",
	description = "Allows players to highlight entities and place markers in the world",
	version		= "1.0.0",
	url			= "https://github.com/dysphie/nmrih-ping-system"
};

ConVar cvEnabled;
ConVar cvLifetime;
ConVar cvColorR;
ConVar cvColorG;
ConVar cvColorB;
ConVar cvTraceWidth;
ConVar cvRange;
ConVar cvIcon;
ConVar cvIconOffset;
ConVar cvBucketSize;
ConVar cvTokensPerSecond;
ConVar cvSound;

ConVar cvAllowNPCs;
ConVar cvAllowPlayers;

ConVar cvCircleSegments;
ConVar cvCircleRadius;

ConVar cvAllowDead;

// ConVar cvTextLocation;

int	   g_LaserIndex;
int	   g_HaloIndex;

float  tokens;
float  lastUpdate;

Cookie optOutCookie;

public void OnPluginStart()
{
	optOutCookie = new Cookie("disable_player_pings", "Toggles seeing player pings", CookieAccess_Private);

	SetCookieMenuItem(CustomCookieMenu, 0, "Player Pings");

	LoadTranslations("ping.phrases");

	cvEnabled		  = CreateConVar("sm_ping_enabled", "1", "Whether player pings are enabled");
	cvTokensPerSecond = CreateConVar("sm_ping_cooldown_tokens_per_second", "0.05", "Tokens added to the bucket per second");
	cvBucketSize	  = CreateConVar("sm_ping_cooldown_bucket_size", "3", "Number of command tokens that fit in the cooldown bucket");
	cvIconOffset	  = CreateConVar("sm_ping_icon_height_offset", "30.0", "Offset ping icon from ping position by this amount");
	cvColorR		  = CreateConVar("sm_ping_color_r", "10", "The red color component for player pings");
	cvColorG		  = CreateConVar("sm_ping_color_g", "224", "The green color component for player pings");
	cvColorB		  = CreateConVar("sm_ping_color_b", "247", "The blue color component for player pings");

	// TODO: instructors have a hard limit of 25.6 seconds lifetime, we should bypass this by sending multiple, clamp the cvar for now
	// DataTable warning: [unknown]: Out-of-range value (60.000000/25.600000) in SendPropFloat 'm_fLife', clamping.
	cvLifetime		  = CreateConVar("sm_ping_lifetime", "8", "The lifetime of player pings in seconds", _, true, 1.0, true, 25.6);

	cvTraceWidth	  = CreateConVar("sm_ping_trace_width", "20", "The width of the player ping trace in game units");
	cvRange			  = CreateConVar("sm_ping_range", "32000", "The maximum reach of the player ping trace in game units");
	cvIcon			  = CreateConVar("sm_ping_icon", "icon_interact", "The icon used for player pings. Empty to disable");
	cvSound			  = CreateConVar("sm_ping_sound", "ui/hint.wav", "The sound used for player pings");
	cvCircleRadius	  = CreateConVar("sm_ping_circle_radius", "9.0", "Radius of the ping circle");
	cvCircleSegments  = CreateConVar("sm_ping_circle_segments", "10", "How many straight lines make up the ping circle");
	cvAllowPlayers	  = CreateConVar("sm_ping_players", "0", "Whether pings can target other players");
	cvAllowNPCs		  = CreateConVar("sm_ping_npcs", "0", "Whether pings can target zombies");
	cvAllowDead		  = CreateConVar("sm_ping_dead_can_use", "1", "Whether dead players can ping");

	// TODO
	// cvTextLocation = CreateConVar("sm_ping_text_location", "0", "Where to place the ping text. 0 = On screen, 1 = In the world");

	cvSound.AddChangeHook(OnPingSoundConVarChanged);

	AutoExecConfig(true, "ping");
	RegConsoleCmd("sm_ping", Cmd_Ping, "Place a marker on the location you are pointing at");
}

void CustomCookieMenu(int client, CookieMenuAction action, any info, char[] buffer, int maxlen)
{
	ShowPingSettingsMenu(client);
}

void ShowPingSettingsMenu(int client)
{
	Menu menu = new Menu(MainMenuHandler, MenuAction_DisplayItem);

	char buffer[255];
	FormatEx(buffer, sizeof(buffer), "%T", "Ping Settings Title", client);
	menu.SetTitle(buffer);

	bool optedOut = optOutCookie.GetInt(client) != 0;

	FormatEx(buffer, sizeof(buffer), "%T: %T", "Setting: Toggle", client,
			 optedOut ? "Cookie Disabled" : "Cookie Enabled", client);

	menu.AddItem("toggle", buffer);
}

int MainMenuHandler(Menu menu, MenuAction action, int param1, int param2)
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
			bool optedOut = optOutCookie.GetInt(client) != 0;
			optOutCookie.SetInt(client, !optedOut);
			ShowPingSettingsMenu(client);
		}
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
		if (!(oldButtons & IN_USE))
		{
			buttons &= ~IN_USE;
			DoPing(client, cvLifetime.IntValue);
		}
	}

	return Plugin_Continue;
}

Action Cmd_Ping(int client, int args)
{
	if (!IsDedicatedServer() && GetCmdReplySource() == SM_REPLY_TO_CONSOLE)
	{
		client = FindEntityByClassname(-1, "player");
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

	DoPing(client, duration);
	return Plugin_Handled;
}

void DoPing(int client, int duration)
{
	if (!CanUsePing(client))
	{
		CPrintToChat(client, "%t", "On Cooldown");
		return;
	}

	float eyeAng[3], eyePos[3];
	GetClientEyeAngles(client, eyeAng);
	GetClientEyePosition(client, eyePos);

	// Start with an accurate trace ray
	Handle rayTrace = TR_TraceRayFilterEx(eyePos, eyeAng, MASK_ALL, RayType_Infinite, TraceFilter_IgnoreBlacklisted, client);
	int	   rayEnt	= TR_GetEntityIndex(rayTrace);

	// Check if we hit an entity with the ray
	if (IsValidEdict(rayEnt) && CouldEntityGlow(rayEnt))
	{
		float endPos[3];
		TR_GetEndPosition(endPos);

		PingEntity(rayEnt, client, duration);
		delete rayTrace;
		return;
	}

	// If we hit nothing, try again using a swept hull
	float hullEnd[3];
	ForwardVector(eyePos, eyeAng, cvRange.FloatValue, hullEnd);

	float traceWidth = cvTraceWidth.FloatValue;

	float hullMins[3];
	hullMins[0] = -traceWidth;
	hullMins[1] = -traceWidth;
	hullMins[2] = -traceWidth;

	float hullMaxs[3];
	hullMaxs[0]		 = traceWidth;
	hullMaxs[1]		 = traceWidth;
	hullMaxs[2]		 = traceWidth;

	Handle hullTrace = TR_TraceHullFilterEx(eyePos, hullEnd, hullMins, hullMaxs, MASK_ALL, TraceFilter_IgnoreBlacklisted, client);

	// if (cvDebugPing.BoolValue) DrawSweptBox(eyePos, hullEnd, hullMins, hullMaxs, .g = 255);

	int	   hullEnt	 = TR_GetEntityIndex(hullTrace);

	if (!CouldEntityGlow(hullEnt))
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
		float endPos[3];
		TR_GetEndPosition(endPos, rayTrace);
		PingEntity(hullEnt, client, duration);
	}

	delete hullTrace;
	delete rayTrace;
}

bool CouldEntityGlow(int entity)
{
	return entity > 0 && HasEntProp(entity, Prop_Data, "m_bIsGlowable") && HasEntProp(entity, Prop_Data, "m_clrGlowColor") && HasEntProp(entity, Prop_Data, "m_flGlowDistance");
}

void PingWorld(float pos[3], float normal[3], int client, int duration)
{
	// Create something for our instructor to latch onto
	int entity = CreateEntityByName("info_target_instructor_hint");
	TeleportEntity(entity, pos);
	DispatchSpawn(entity);

	// Give it time to network
	DataPack data;
	CreateDataTimer(0.1, Frame_PointAtEntity, data);
	data.WriteCell(EntIndexToEntRef(entity));
	data.WriteCell(GetClientSerial(client));
	data.WriteCell(duration);
	data.WriteFloatArray(pos, 3);

	// Delete helper entity after ping has expired
	CreateTimer(cvLifetime.FloatValue + 0.1, Timer_DeleteHelperEntity, EntIndexToEntRef(entity));

	// Now draw beam circle where we hit
	int rgba[4];
	GetPingColor(rgba);
	DrawCircleOnSurface(pos, cvCircleRadius.FloatValue, cvCircleSegments.IntValue, normal, duration);
}

void PingEntity(int entity, int client, int duration)
{
	HighlightEntity(entity, duration);
	PointAtEntity(entity, client, duration);
}

void GetPingColor(int rgba[4])
{
	rgba[0] = cvColorR.IntValue;
	rgba[1] = cvColorG.IntValue;
	rgba[2] = cvColorB.IntValue;
	rgba[3] = 255;
}

Action Frame_PointAtEntity(Handle timer, DataPack data)
{
	data.Reset();
	int	  entity   = EntRefToEntIndex(data.ReadCell());
	int	  player   = GetClientFromSerial(data.ReadCell());
	int	  duration = data.ReadCell();

	float pingPos[3];
	data.ReadFloatArray(pingPos, sizeof(pingPos));

	PointAtEntity(entity, player, duration);
	return Plugin_Stop;
}

Action Timer_DeleteHelperEntity(Handle timer, int entRef)
{
	if (IsValidEntity(entRef))
	{
		RemoveEntity(entRef);
	}

	return Plugin_Continue;
}

void HighlightEntity(int entity, int duration)
{
	char classname[80];
	GetEntityClassname(entity, classname, sizeof(classname));

	char rgb[40];
	FormatEx(rgb, sizeof(rgb), "%d %d %d",
			 cvColorR.IntValue, cvColorG.IntValue, cvColorB.IntValue);

	bool  oldIsGlowable = GetEntProp(entity, Prop_Send, "m_bIsGlowable") != 0;
	int	  oldGlowColor	= GetEntProp(entity, Prop_Send, "m_clrGlowColor");
	float oldGlowDist	= GetEntPropFloat(entity, Prop_Send, "m_flGlowDistance");

	// TODO: Why don't we use above dataprops for these?
	DispatchKeyValue(entity, "glowable", "1");
	DispatchKeyValue(entity, "glowdistance", "-1");
	DispatchKeyValue(entity, "glowcolor", rgb);
	AcceptEntityInput(entity, "EnableGlow", entity, entity);

	DataPack data;
	CreateDataTimer((float)(duration), Timer_UnhighlightEntity, data);
	data.WriteCell(EntIndexToEntRef(entity));
	data.WriteCell(oldIsGlowable);
	data.WriteCell(oldGlowColor);
	data.WriteFloat(oldGlowDist);
}

Action Timer_UnhighlightEntity(Handle timer, DataPack data)
{
	data.Reset();
	int entity = EntRefToEntIndex(data.ReadCell());
	if (entity != -1)
	{
		AcceptEntityInput(entity, "DisableGlow", entity, entity);
		SetEntProp(entity, Prop_Send, "m_bIsGlowable", data.ReadCell());
		SetEntProp(entity, Prop_Send, "m_clrGlowColor", data.ReadCell());
		SetEntPropFloat(entity, Prop_Send, "m_flGlowDistance", data.ReadFloat());
	}

	return Plugin_Continue;
}

public bool TraceFilter_IgnoreBlacklisted(int entity, int contentMask, int ignore)
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

	return true;
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

void PointAtEntity(int entity, int issuer, int duration)
{
	int rgba[4];
	GetPingColor(rgba);

	char rgb[40];
	FormatEx(rgb, sizeof(rgb), "%d,%d,%d",
			 rgba[0], rgba[1], rgba[2]);

	char icon[32];
	cvIcon.GetString(icon, sizeof(icon));

	char hintKey[32];
	FloatToString(GetGameTime(), hintKey, sizeof(hintKey));

	char hintSound[PLATFORM_MAX_PATH];
	cvSound.GetString(hintSound, sizeof(hintSound));

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || !HasPingsEnabled(client))
		{
			continue;
		}

		char caption[255];
		FormatEx(caption, sizeof(caption), "%T", "Player Ping", client, issuer);

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
		event.SetString("hint_color", rgb);
		event.SetFloat("hint_icon_offset", cvIconOffset.FloatValue);
		event.SetFloat("hint_range", cvRange.FloatValue);
		event.SetInt("hint_flags", 0);
		event.SetString("hint_binding", "");
		event.SetBool("hint_allow_nodraw_target", true);
		event.SetBool("hint_nooffscreen", icon[0] == '\0');
		event.SetBool("hint_forcecaption", false);
		event.SetBool("hint_local_player_only", false);
		event.SetString("hint_start_sound", "common/null.wav");	   // We will play our own which isn't buggy
		event.SetInt("hint_target_pos", 2);						   // World center
		event.FireToClient(client);

		EmitSoundToClient(client, hintSound, SOUND_FROM_PLAYER);

		event.Cancel();
	}
}

void TE_SendBeam(const float start[3], const float end[3], int duration)
{
	int rgba[4];
	GetPingColor(rgba);

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

	TE_SendToAll();	   // FIXME: Not all clients want pings to be displayed
}

public void OnMapStart()
{
	tokens		 = cvBucketSize.FloatValue;
	lastUpdate	 = 0.0;

	g_LaserIndex = PrecacheModel("materials/sprites/laserbeam.vmt");
	g_HaloIndex	 = PrecacheModel("materials/sprites/halo01.vmt");

	PrecacheSound("common/null.wav");

	char hintSound[PLATFORM_MAX_PATH];
	cvSound.GetString(hintSound, sizeof(hintSound));
	if (hintSound[0])
	{
		PrecacheSound(hintSound);
	}
}

// void DrawCircleOnSurface(const float center[3], const float radius, const int segments, const float normal[3], int duration)
// {
// 	float prevPoint[3];
// 	float currPoint[3];

// 	// Compute two orthogonal vectors to the normal vector
// 	float tangent1[3];
// 	float tangent2[3];
// 	ComputeTangents(normal, tangent1, tangent2);

// 	NormalizeVector(tangent1, tangent1);
// 	NormalizeVector(tangent2, tangent2);

// 	// Compute the points on the circumference
// 	for (int i = 0; i <= segments; i++)
// 	{
// 		float angle	 = (2 * MATH_PI / segments) * i;
// 		currPoint[0] = center[0] - (-1.0 * normal[0]) + (radius * Cosine(angle) * tangent1[0]) + (radius * Sine(angle) * tangent2[0]);
// 		currPoint[1] = center[1] - (-1.0 * normal[1]) + (radius * Cosine(angle) * tangent1[1]) + (radius * Sine(angle) * tangent2[1]);
// 		currPoint[2] = center[2] - (-1.0 * normal[2]) + (radius * Cosine(angle) * tangent1[2]) + (radius * Sine(angle) * tangent2[2]);

// 		if (prevPoint[0] && prevPoint[1] && prevPoint[2])
// 		{
// 			TE_SendBeam(prevPoint, currPoint, duration);
// 			// DrawLine(prevPoint, currPoint, .r = 255, .duration = 20.0, .noDepthTest = true);
// 		}

// 		prevPoint[0] = currPoint[0];
// 		prevPoint[1] = currPoint[1];
// 		prevPoint[2] = currPoint[2];
// 	}
// }

void DrawCircleOnSurface(const float center[3], const float radius, const int segments, const float normal[3], int duration)
{
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
			TE_SendBeam(prevPoint, currPoint, duration);
			// DrawLine(prevPoint, currPoint, .r = 255, .duration = 20.0, .noDepthTest = true);
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

bool CanUsePing(int client)
{
	if (CheckCommandAccess(client, "ping_cooldown_immunity", ADMFLAG_PING))
	{
		return true;
	}

	float currentTime  = GetGameTime();
	float time_elapsed = currentTime - lastUpdate;
	float tokensToAdd  = time_elapsed * cvTokensPerSecond.FloatValue;
	tokens			   = min(tokens + tokensToAdd, cvBucketSize.FloatValue);
	lastUpdate		   = currentTime;

	if (tokens >= 1.0)
	{
		tokens -= 1.0;
		return true;
	}

	return false;
}

any min(any x, any y)
{
	return (x < y) ? x : y;
}

bool HasPingsEnabled(int client)
{
	if (!AreClientCookiesCached(client))
	{
		return true;
	}

	return optOutCookie.GetInt(client) == 0;
}