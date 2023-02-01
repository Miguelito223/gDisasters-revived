gDisasters.DayNightSystem        = {}
gDisasters.DayNightSystem.InternalVars = {}

gDisasters.DayNightSystem.InternalVars.enabled = GetConVar("gdisasters_dnc_enabled")
gDisasters.DayNightSystem.InternalVars.paused =  GetConVar("gdisasters_dnc_paused")
gDisasters.DayNightSystem.InternalVars.realtime =  GetConVar("gdisasters_dnc_realtime")
gDisasters.DayNightSystem.InternalVars.logging =  GetConVar("gdisasters_dnc_log")

gDisasters.DayNightSystem.InternalVars.length_day = GetConVar( "gdisasters_dnc_length_day")
gDisasters.DayNightSystem.InternalVars.length_night = GetConVar( "gdisasters_dnc_length_night")

gDisasters.DayNightSystem.InternalVars.version = 2.0;
gDisasters.DayNightSystem.InternalVars.dev = false;

gDisasters.DayNightSystem.InternalVars.HeightMin = 300;

function gdisasters_dnc_log( ... )

    if ( gDisasters.DayNightSystem.InternalVars.logging:GetInt() < 1 ) then return end

    print( "[day and night] " .. string.format( ... ) .. "\n" );

end

function gdisasters_dnc_Outside( pos )

    if ( pos != nil ) then

        local trace = { };
        trace.start = pos;
        trace.endpos = trace.start + Vector( 0, 0, 32768 );
        trace.mask = MASK_BLOCKLOS;

        local tr = util.TraceLine( trace );

        gDisasters.DayNightSystem.InternalVars.HeightMin = ( tr.HitPos - trace.start ):Length();

        if ( tr.StartSolid ) then return false end
        if ( tr.HitSky ) then return true end

    end

    return false;

end

function gdisasters_dnc_outside( pos )

    return gdisasters_dnc_Outside( pos );

end

-- usergroup support
local meta = FindMetaTable( "Player" )

function meta:gdisasters_dnc_Admin()

    return self:IsSuperAdmin() or self:IsAdmin();

end
    
if (SERVER) then
    
    local TIME_NOON			= 12;		-- 12:00pm
    local TIME_MIDNIGHT		= 0;		-- 12:00am
    local TIME_DAWN_START	= 4;		-- 4:00am
    local TIME_DAWN_END		= 6.5;		-- 6:30am
    local TIME_DUSK_START	= 19;		-- 7:00pm;
    local TIME_DUSK_END		= 20.5;		-- 8:30pm;
    
    local STYLE_LOW			= string.byte( 'a' );		-- style for night time
    local STYLE_HIGH		= string.byte( 'm' );		-- style for day time
    
    local NIGHT				= 0;
    local DAWN				= 1;
    local DAY				= 2;
    local DUSK				= 3;

    local SKYPAINT =
    {
        [DAWN] =
        {
		    TopColor		= Vector( 0.20,0.50,1.00 ),
		    BottomColor		= Vector(  1, 0.48, 0  ),
		    FadeBias		= 1,
		    HDRScale		= 0.26,
		    StarScale		= 0.66,
		    StarFade		= 0.0,	-- Do not change!
            StarSpeed 		= 0.02,
		    DuskScale		= 1,
		    DuskIntensity	= 1,
		    DuskColor		= Vector( 1, 0.2, 0 ),
		    SunColor		= Vector( 0.2, 0.1, 0 ),
		    SunSize			= 0.34,
        },
        [DAY] =
        {
		    TopColor		= Vector(0.20,0.50,1.00),
		    BottomColor		= Vector(0.80,1.00,1.00),
		    FadeBias		= 1.00,
		    HDRScale		= 0.66,
		    StarScale		= 0.50,
		    StarFade		= 1.5,	-- Do not change!
            StarSpeed 		= 0.01,
		    DuskScale		= 0.5,
		    DuskIntensity	= 1.00,
		    DuskColor		= Vector(1.00,0.20,0.00),
		    SunColor		= Vector(0.20,0.10,0.00 ),
		    SunSize			= 2.00,
        },
        [DUSK] =
        {
		    TopColor		= Vector( 0.20,0.50,1.00 ),
		    BottomColor		= Vector( 1, 0.48, 0 ),
		    FadeBias		= 1,
		    HDRScale		= 0.36,
		    StarScale		= 0.66,
		    StarFade		= 0.0,	-- Do not change!
            StarSpeed 		= 0.01,
		    DuskScale		= 1,
		    DuskIntensity	= 5.31,
		    DuskColor		= Vector( 1.00,0.20,0.00 ),
		    SunColor		= Vector( 0.83, 0.45, 0.11 ),
		    SunSize			= 0.34,
        },
        [NIGHT] =
        {
		    TopColor		= Vector( 0.00, 0.00, 0.00 ),
		    BottomColor		= Vector(  0.00, 0.00, 0.00 ),
		    FadeBias		= 0.27,
		    HDRScale		= 0.19,
		    StarScale		= 0.66,
		    StarFade		= 5.0,	-- Do not change!
            StarSpeed 		= 0.01,
		    DuskScale		= 0,
		    DuskIntensity	= 0,
		    DuskColor		= Vector(  0.00, 0.00, 0.00 ),
		    SunColor		= Vector( 0.83, 0.45, 0.11 ),
		    SunSize			= 0.0,
        }

    };

    gDisasters.DayNightSystem.Start =
    {
        m_InitEntities = false,
        m_OldSkyName = "unknown",
        m_Time = 6.5,
        m_LastPeriod = NIGHT,
        m_LastStyle = '.',
        m_Cloudy = false,
        m_Paused = false,

        -- to easily hook functions within our own object instance
        Hook = function( this, name )

            local func = this[name];
            local function Wrapper( ... )
                func( this, ... );
            end

            hook.Add( name, string.format( "gdisasters_dnc.%s", tostring( this ), name ), Wrapper );

        end,

        LightStyle = function( self, style, force )

            if ( tostring( self.m_LastStyle ) == tostring( style ) and (force == nil or force == false) ) then return end

            --gdisasters.daynightsystem.internalvars.log( "LightStyle set to " .. tostring(style) .. " " .. tostring(self.m_LastStyle) .. " " .. tostring(force) );

            if ( IsValid( self.m_LightEnvironment ) ) then

                self.m_LightEnvironment:Fire( "FadeToPattern", tostring( style ) );

            else

                engine.LightStyle( 0, style );

                timer.Simple( 0.1, function()

                    net.Start( "gd_maplight_cl" );
                    net.Broadcast();

                end );

            end

            self.m_LastStyle = style;

        end,

        Initialize = function( self )

            self.m_OldSkyName = GetConVar("sv_skyname"):GetString();

            self:Hook( "Think" );
           

            gdisasters_dnc_log( "Day & Night version %s initializing.", tostring( gDisasters.DayNightSystem.InternalVars.version ) );

        end,

        RenderMoon = function( self )

            self.Texture1                          = "atmosphere/moon/1"
            self.Texture2                          = "atmosphere/moon/2"
            self.Texture3                          = "atmosphere/moon/3"
            self.Texture4                          = "atmosphere/moon/4"
            self.Texture5                          = "atmosphere/moon/5"
            self.Texture6                          = "atmosphere/moon/6"
            self.Texture7                          = "atmosphere/moon/7"
            self.Texture8                          = "atmosphere/moon/8"
            self.Texture9                          = "atmosphere/moon/9"
            self.Texture10                         = "atmosphere/moon/10"
            self.Texture11                         = "atmosphere/moon/11"
            self.Texture12                         = "atmosphere/moon/12"
            self.Texture13                         = "atmosphere/moon/13"
            self.Texture14                         = "atmosphere/moon/14"
            self.Texture15                         = "atmosphere/moon/15"
            self.Texture16                         = "atmosphere/moon/16"
            
            local moonAlpha = 0;
            local moonMat = Material( self.Texture9  );
            moonMat:SetInt( "$additive", 0 );
            moonMat:SetInt( "$translucent", 0 );

            print("lol")

            if ( self.m_Time < TIME_DAWN_START or self.m_Time > TIME_DUSK_END ) then

                local moonSize = GetConVar("gdisasters_dnc_moonsize"):GetFloat();
                local moonPos = gDisasters_GetMoonDir();
                local moonNormal = ( vector_origin - moonPos ):GetNormal();

                

                moonAlpha = Lerp( FrameTime() * 1, moonAlpha, 255 );

                cam.Start3D( vector_origin, angle_zero );
                    render.OverrideDepthEnable( true, false );
                    render.SetMaterial( moonMat );
                    render.DrawQuadEasy( moonPos, moonNormal, moonSize, moonSize, Color( 255, 255, 255, moonAlpha ), -180 );
                    render.OverrideDepthEnable( false, false );
                cam.End3D();
            else
                if ( moonAlpha != 0 ) then
                
                    moonAlpha = 0;
                
                end
            end

            
        end,


        InitEntities = function( self )

            self.m_LightEnvironment = ents.FindByClass( "light_environment" )[1];
            self.m_EnvSun = ents.FindByClass( "env_sun" )[1];
            self.m_EnvSkyPaint = ents.FindByClass( "env_skypaint" )[1];
            self.m_RelayDawn = ents.FindByName( "dawn" )[1];
            self.m_RelayDusk = ents.FindByName( "dusk" )[1];
            self.m_RelayCloudy = ents.FindByName( "cloudy" )[1];

            -- put the sun on the horizon initially
            if ( IsValid( self.m_EnvSun ) ) then
                self.m_EnvSun:SetKeyValue( "sun_dir", "1 0 0" );
            end

            -- log found entities
            -- HACK: Fixes prop lighting since the first pattern change fails to update it.
            if ( IsValid( self.m_LightEnvironment ) ) then
                gdisasters_dnc_log( "Found light_environment" );

                self:LightStyle( "a", true );
            else
                gdisasters_dnc_log( "No light_environment, using engine.LightStyle instead." );

                -- a is too dark for use with engine.LightStyle, bugs out
                STYLE_LOW = string.byte( "b" );
                self:LightStyle( "b", true );
            end

            if ( IsValid( self.m_EnvSun ) ) then
                gdisasters_dnc_log( "Found env_sun" );
            end

            if ( IsValid( self.m_EnvSkyPaint ) ) then

                gdisasters_dnc_log( "Found env_skypaint" );

            else

                local skyPaint = ents.Create( "env_skypaint" );
                skyPaint:Spawn();
                skyPaint:Activate();

                self.m_EnvSkyPaint = skyPaint;

                gdisasters_dnc_log( "Created env_skypaint" );

            end

            self.m_EnvSkyPaint:SetStarTexture( "skybox/starfield" );

            self.m_InitEntities = true;

        end,

        Think = function( self )

            if ( gDisasters.DayNightSystem.InternalVars.enabled:GetInt() < 1 ) then return end
            if ( !self.m_InitEntities ) then self:InitEntities(); end

            local timeLen = 3600;
            if (self.m_Time > TIME_DUSK_START or self.m_Time < TIME_DAWN_END) then
                timeLen = gDisasters.DayNightSystem.InternalVars.length_night:GetInt();
            else
                timeLen = gDisasters.DayNightSystem.InternalVars.length_day:GetInt();
            end

            if ( !self.m_Paused and gDisasters.DayNightSystem.InternalVars.paused:GetInt() <= 0)  then
                if ( gDisasters.DayNightSystem.InternalVars.realtime:GetInt() <= 0 ) then
                    self.m_Time = self.m_Time + ( 24 / timeLen ) * FrameTime();
                    if ( self.m_Time > 24 ) then
                        self.m_Time = 0;
                    end
                else
                    self.m_Time = self:GetRealTime();
                end
            end

            -- since our dawn/dusk periods last several hours find the mid point of them
            local dawnMidPoint = ( TIME_DAWN_END + TIME_DAWN_START ) / 2;
            local duskMidPoint = ( TIME_DUSK_END + TIME_DUSK_START ) / 2;

            -- dawn/dusk/night events
            if ( self.m_Time >= TIME_DUSK_END) then
                
                if ( self.m_LastPeriod != NIGHT ) then
                    self.m_LastPeriod = NIGHT;
                end

            elseif ( self.m_Time >= duskMidPoint ) then
                if ( self.m_LastPeriod != DUSK ) then
                    if ( IsValid( self.m_RelayDusk ) ) then
                        self.m_RelayDusk:Fire( "Trigger", "" );
                    end

                    -- disabled because the clouds at night look pretty awful..
                    --self.m_Cloudy = math.random() > 0.5;
                    self.m_Cloudy = false;

                    -- at dawn select if we should display clouds for night or not (50% chance)
                    if ( IsValid( self.m_EnvSkyPaint ) ) then
                        if ( self.m_Cloudy ) then
                            self.m_EnvSkyPaint:SetStarTexture( "skybox/clouds" );
                        else
                            self.m_EnvSkyPaint:SetStarTexture( "skybox/starfield" );
                        end
                    end

                    self.m_LastPeriod = DUSK;
                end

            elseif ( self.m_Time >= dawnMidPoint ) then
                if ( self.m_LastPeriod != DAWN ) then
                    if ( IsValid( self.m_RelayDawn ) ) then
                        self.m_RelayDawn:Fire( "Trigger", "" );
                    end

                    -- disabled because clouds during transitions looks pretty awful, too
                    --self.m_Cloudy = math.random() > 0.5;
                    self.m_Cloudy = false;

                    -- at dawn select if we should display clouds for day or not (50% chance)
                    if ( IsValid( self.m_EnvSkyPaint ) ) then
                        if ( self.m_Cloudy ) then
                            self.m_EnvSkyPaint:SetStarTexture( "skybox/clouds" );
                            SKYPAINT[DAY].StarFade = 1.5;
                        else
                            SKYPAINT[DAY].StarFade = 0;
                        end
                    end

                    self.m_LastPeriod = DAWN;
                end

            elseif ( self.m_Time >= TIME_DAWN_START) then
                if ( self.m_LastPeriod != DAY ) then
                    self.m_LastPeriod = DAY;
                end

            end

            -- light_environment
            local lightfrac = 0;

            if ( self.m_Time >= dawnMidPoint and self.m_Time < TIME_NOON ) then
                lightfrac = math.EaseInOut( ( self.m_Time - dawnMidPoint ) / ( TIME_NOON - dawnMidPoint ), 0, 1 );
            elseif ( self.m_Time >= TIME_NOON and self.m_Time < duskMidPoint ) then
                lightfrac = 1 - math.EaseInOut( ( self.m_Time - TIME_NOON ) / ( duskMidPoint - TIME_NOON ), 1, 0 );
            end

            local style = string.char( math.floor( Lerp( lightfrac, STYLE_LOW, STYLE_HIGH ) + 0.5 ) );

            self:LightStyle( style );

            -- env_sun
            if ( IsValid( self.m_EnvSun ) ) then
                local sunfrac = 1 - ( ( self.m_Time - TIME_DAWN_START ) / ( TIME_DUSK_END - TIME_DAWN_START ) );
                local angle = Angle( -180 * sunfrac, 15, 0 );

                self.m_EnvSun:SetKeyValue( "sun_dir", tostring( angle:Forward() ) );
                SetGlobalAngle("gdSunDir", angle:Forward() )

            end

            -- env_skypaint
            if ( IsValid( self.m_EnvSkyPaint ) ) then

                if ( IsValid( self.m_EnvSun ) ) then
                    self.m_EnvSkyPaint:SetSunNormal( self.m_EnvSun:GetInternalVariable( "m_vDirection" ) );
                end

                local cur = NIGHT;
                local next = NIGHT;
                local frac = 0;
                local ease = 0.3;

                data = {}
			    data.Color = Color(0,0,0)
			    data.DensityCurrent = 0
			    data.DensityMax     = 0.8
			    data.DensityMin     = 0.1
			    data.EndMax         = 10050
			    data.EndMin         = 0
			    data.EndMinCurrent  = 0
			    data.EndMaxCurrent  = 0   

                if ( self.m_Time >= TIME_DAWN_START and self.m_Time < dawnMidPoint ) then
                    cur = NIGHT;
                    next = DAWN;
                    frac = math.EaseInOut( ( self.m_Time - TIME_DAWN_START ) / ( dawnMidPoint - TIME_DAWN_START ), ease, ease );
                elseif ( self.m_Time >= dawnMidPoint and self.m_Time < TIME_DAWN_END ) then
                    cur = DAWN;
                    next = DAY;
                    frac = math.EaseInOut( ( self.m_Time - dawnMidPoint ) / ( TIME_DAWN_END - dawnMidPoint ), ease, ease );
                elseif ( self.m_Time >= TIME_DUSK_START and self.m_Time < duskMidPoint ) then
                    cur = DAY;
                    next = DUSK;
                    frac = math.EaseInOut( ( self.m_Time - TIME_DUSK_START ) / ( duskMidPoint - TIME_DUSK_START ), ease, ease );
                elseif ( self.m_Time >= duskMidPoint and self.m_Time < TIME_DUSK_END ) then
                    cur = DUSK;
                    next = NIGHT;
                    frac = math.EaseInOut( ( self.m_Time - duskMidPoint ) / ( TIME_DUSK_END - duskMidPoint ), ease, ease );
                elseif ( self.m_Time >= TIME_DAWN_END and self.m_Time <= TIME_DUSK_END ) then
                    cur = DAY;
                    next = DAY;
                end

                self.m_EnvSkyPaint:SetTopColor( LerpVector( frac, SKYPAINT[cur].TopColor, SKYPAINT[next].TopColor ) );
                self.m_EnvSkyPaint:SetBottomColor( LerpVector( frac, SKYPAINT[cur].BottomColor, SKYPAINT[next].BottomColor ) );
                self.m_EnvSkyPaint:SetSunColor( LerpVector( frac, SKYPAINT[cur].SunColor, SKYPAINT[next].SunColor ) );
                self.m_EnvSkyPaint:SetDuskColor( LerpVector( frac, SKYPAINT[cur].DuskColor, SKYPAINT[next].DuskColor ) );
                self.m_EnvSkyPaint:SetFadeBias( Lerp( frac, SKYPAINT[cur].FadeBias, SKYPAINT[next].FadeBias ) );
                self.m_EnvSkyPaint:SetHDRScale( Lerp( frac, SKYPAINT[cur].HDRScale, SKYPAINT[next].HDRScale ) );
                self.m_EnvSkyPaint:SetDuskScale( Lerp( frac, SKYPAINT[cur].DuskScale, SKYPAINT[next].DuskScale ) );
                self.m_EnvSkyPaint:SetDuskIntensity( Lerp( frac, SKYPAINT[cur].DuskIntensity, SKYPAINT[next].DuskIntensity ) );
                self.m_EnvSkyPaint:SetSunSize( (Lerp( frac, SKYPAINT[cur].SunSize, SKYPAINT[next].SunSize )) );
                

                self.m_EnvSkyPaint:SetStarFade( SKYPAINT[next].StarFade );
                self.m_EnvSkyPaint:SetStarScale( SKYPAINT[next].StarScale );
                self.m_EnvSkyPaint:SetStarSpeed( SKYPAINT[next].StarSpeed );

            end

        end,

        TogglePause = function( self )

            self.m_Paused = !self.m_Paused;

        end,

        SetTime = function( self, time )

            self.m_Time = math.Clamp( time, 0, 24 );

            -- FIXME: we're bypassing the sun code
            if ( IsValid( self.m_EnvSun ) ) then
                self.m_EnvSun:SetKeyValue( "sun_dir", "1 0 0" );
            end

            -- FIXME: we're bypassing the dusk/dawn events
            if ( IsValid( self.m_EnvSkyPaint ) ) then
                self.m_EnvSkyPaint:SetStarTexture( "skybox/starfield" );
                SKYPAINT[DAY].StarFade = 0;
            end

        end,

        GetRealTime = function( self )

            local t = os.date( "*t" );

            return t.hour + (t.min / 60) + (t.sec / 3600);

        end,

        GetTime = function( self )

            return (gdisasters.daynightsystem.internalvars.realtime:GetInt() <= 0 and self.m_Time or self:GetRealTime());

        end,
    };

    -- global handle for debugging
    gDisasters.DayNightSystem.InternalVars.Global = gDisasters.DayNightSystem.Start;

    hook.Add( "Initialize", "gdisasters_dnc_Init", function()

       gDisasters.DayNightSystem.Start:Initialize();

    end );

    hook.Add("PostDrawSkyBox", "gdisasters_dnc_DrawMoon", function() 
        
        gDisasters.DayNightSystem.Start:RenderMoon();
    
    end)

    concommand.Add( "gdisasters_dnc_pause", function( pl, cmd, args )

        if ( !IsValid( pl ) or !pl:gdisasters_dnc_Admin() ) then return end

        gDisasters.DayNightSystem.Start:TogglePause();

        if ( IsValid( pl ) ) then

            pl:PrintMessage( HUD_PRINTCONSOLE, "DNC is " .. (gDisasters.DayNightSystem.varinterval.m_Paused and "paused" or "no longer paused") );

        else

            print( "DNC is " .. (gDisasters.DayNightSystem.Start.m_Paused and "paused" or "no longer paused") );

        end

    end );

    concommand.Add( "gdisasters_dnc_settime", function( pl, cmd, args )

        if ( !IsValid( pl ) or !pl:gdisasters_dnc_Admin() ) then return end

        gDisasters.DayNightSystem.Start:SetTime( tonumber( args[1] or "0" ) );

    end );

    concommand.Add( "gdisasters_dnc_time", function( pl, cmd, args )

        local time = gDisasters.DayNightSystem.Start:GetTime();
        local hours = math.floor( time );
        local minutes = ( time - hours ) * 60;

        if ( IsValid( pl ) ) then

            pl:PrintMessage( HUD_PRINTCONSOLE, string.format( "The current time is %s", string.format( "%02i:%02i", hours, minutes ) ) );

        else

            print( string.format( "The current time is %s", string.format( "%02i:%02i", hours, minutes ) ) );

        end

    end );

    function gdisasters_dnc_Message( pl, ... )

        net.Start( "gd_dnc_message" );
        net.WriteTable( { ... } );
        net.Send( pl );

    end

    function gdisasters_dnc_MessageAll( ... )

        net.Start( "gd_dnc_message" );
        net.WriteTable( { ... } );
        net.Broadcast();

    end

    -- Net

    -- Hacky workaround to make it possible for admins to change server cvars on dedicated servers

    concommand.Add( "gdisasters_dnc_reset", function( pl, cmd, args )

        if ( IsValid( pl ) and !pl:gdisasters_dnc_Admin() ) then return end

        game.ConsoleCommand( "gdisasters.daynightsystem.internalvars.enabled 1\n" );
        game.ConsoleCommand( "gdisasters.daynightsystem.internalvars.paused 0\n" );
        game.ConsoleCommand( "gdisasters.daynightsystem.internalvars.realtime 0\n" );
        game.ConsoleCommand( "gdisasters.daynightsystem.internalvars.length_day 3600\n" );
        game.ConsoleCommand( "gdisasters.daynightsystem.internalvars.length_night 3600\n" );

        if ( IsValid( pl ) ) then

            pl:PrintMessage( HUD_PRINTCONSOLE, "Day & Night server settings reset." );

        else

            print( "Day & Night server settings reset." );

        end

    end );

    -- adds support for saving and restoring day & night values
    saverestore.AddSaveHook( "gdisasters_dnc_Save", function( save )
        local gdisasters_dnc_data = {
            gdisasters_dnc_time = gDisasters.DayNightSystem.Start.m_Time
        }

        saverestore.WriteTable(gdisasters_dnc_data, save);

        print("Day & Night save hook called!\n");
    end);

    saverestore.AddRestoreHook( "gdisasters_dnc_Restore", function( save )
        local tbl = saverestore.ReadTable( save );

        if (tbl.gdisasters_dnc_time != nil) then
            gDisasters.DayNightSystem.Start:SetTime(tbl.gdisasters_dnc_time);
        end

        print("Day & Night saverestore hook called!\n");
    end);

end

if (CLIENT) then
    
	hook.Add( "InitPostEntity", "gDisastersFirstJoinLightmaps", function()

    	render.RedownloadAllLightmaps()

    end)

end