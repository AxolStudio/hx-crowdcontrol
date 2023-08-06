package crowdcontrol;

import haxe.Http;
import haxe.Json;
import haxe.SysTools;
import haxe.Timer;
import haxe.net.WebSocket;
import jwt.JWT;
import uuid.Uuid;

class CrowdControl
{
	private static inline var SOCKET_URL:String = "wss://pubsub.crowdcontrol.live/";

	private static inline var AUTH_URL:String = "https://auth.crowdcontrol.live/?connectionID=";

	private static inline var HTTP_URL:String = "https://trpc.crowdcontrol.live/";

	private static inline var INTERACTION_URL:String = "https://interact.crowdcontrol.live/#/";

	private static var ccUID:String = "";

	/* the current status of the Crowd Control System when = CCStatus.INITIALIZED then it's ready to be used.*/
	public static var Status:CCStatus = CCStatus.NONE;

	/* the current status of the Crowd Control Session when = CCStatus.INITIALIZED then it's ready to be used.*/
	public static var SessionStatus:CCStatus = CCStatus.NONE;

	private static var timer:Timer;

	private static var ws:WebSocket;

	private static var user:User;

	private static var GamePack:String = "";

	/* While Paused, the Crowd Control System will not process any effects - they will just keep getting put into the queue. */
	public static var Paused(default, set):Bool = true;

	private static var EffectQueue:Array<EffectRequest> = [];

	private static var Effects:Map<String, Effect> = [];

	private static var MAX_TRIES:Int = 5;
	private static var MAX_TIME:Float = 240;

	private static var startTime:Float=0;
	private static var sessionStartTime:Float=0;

	private static var authToken:String="";
	private static var sessionID:String="";

	private static var lastTime:Float =0;
	private static var elapsed:Float = 0;

	/* Do you want to see all the responses? */
	public static var verbose:Bool = false;

	public static var interactURL:String ="";

	/**
	 * Call this to initialize the Crowd Control System
	 * 
	 * @param GamePackID 		The ID of the game pack you are using.
	 */
	public static function Initialize(GamePackID:String):Void
	{
		if (Status != CCStatus.NONE)
			return;

		Status = CCStatus.INITIALIZING;
		startTime = haxe.Timer.stamp();

		if (GamePackID == "")
		{
			throw("GamePackID cannot be empty");
			return;
		}

		GamePack = GamePackID;

		#if (target.threaded )
		sys.thread.Thread.create(() -> {
		#end
		ws = WebSocket.create(SOCKET_URL, null, null, verbose);

		ws.onopen = function()
		{
			if (authToken != "")
			{
				subscribe();
			}
			else
			{
				sendWhoAmI();
			}
		}

		ws.onmessageString = function(message)
		{
			var response:Dynamic = Json.parse(message);

			if (verbose)
				trace("Crowd Control Websocket Response: " + response);

			if (response.type == "whoami")
			{
				var connectionID = response.payload.connectionID;

				openURL(AUTH_URL + connectionID, "_blank");
			}
			else if (response.type == "login-success")
			{
				authToken = response.payload.token;

				var userData:Dynamic = JWT.extract(authToken);

				user = new User(userData.originID, userData.profileType, userData.ccUID, userData.name);

				interactURL =  INTERACTION_URL + user.profileType + "/" + user.originID;
				
				trace("Crowd Control Interaction URL: " + interactURL);

				subscribe();
			}
			else if (response.type == "subscription-result")
			{
				if (response.payload.success != [])
				{
					Status = CCStatus.INITIALIZED;
				}
			}
			else if (response.type == "effect-request")
			{
				if (Effects.exists(response.payload.effect.effectID))
				{
					EffectQueue.push(new EffectRequest(response.payload.effect.effectID, response.payload.requestID, response.payload.effect.duration));
				}
				else
				{
					sendStatus(FAIL_PERMANENT, response.payload.effect.requestID);
				}

			}
		};

		timer = new Timer(100);
		timer.run = function()
		{
			updateTimes();
			
			ws.process();

			if (Status == CCStatus.INITIALIZING)
			{
				if (haxe.Timer.stamp() - startTime > MAX_TIME)
				{
					Status = CCStatus.NONE;
					startTime = 0;
					throw("Crowd Control failed to initialize in time");
					return;
				}
			}
			else if (Status == CCStatus.INITIALIZED && SessionStatus == CCStatus.INITIALIZING)
			{
				if (haxe.Timer.stamp() - sessionStartTime > MAX_TIME)
				{
					SessionStatus = CCStatus.NONE;
					sessionStartTime = 0;
					throw("Crowd Control failed to start session in time");
					return;
				}
			}

			processEffects();
		};
		
		#if (target.threaded )
		});
		#end
	}

	private static function updateTimes():Void
	{
		var currTime:Float = haxe.Timer.stamp();
		elapsed = currTime - lastTime;
		lastTime = currTime;

	}

	/**
	 * This fumction starts a new session. Must be done after the Crowd Control System has been initialized
	 * and before any requests can be recieved.
	 */
	public static function StartSession():Void
	{	
		#if (target.threaded )
		sys.thread.Thread.create(() -> {
		#end
		if (SessionStatus != CCStatus.NONE)
			return;

		if (Status != CCStatus.INITIALIZED)
		{
			throw("Crowd Control has not been initialized yet");
			return;
		}

		SessionStatus = CCStatus.INITIALIZING;
		sessionStartTime = haxe.Timer.stamp();
		sendData(HTTP_URL,"gameSession.startSession", Json.stringify({gamePackID: GamePack, effectReportArgs: []}), (err)->{
			throw("Failed to start session: " + err);
		}, (r)->{
			
			if (verbose)
				trace("Crowd Control Session Start Response: " + r);
			
			var response = Json.parse(r);
			sessionID = response.result.data.gameSessionID;
			if (sessionID != "")
			{
				SessionStatus = CCStatus.INITIALIZED;


				if (verbose)
				{
					trace("Crowd Control Session Started: " + sessionID);
				}
			}
			else
			{
				throw("Failed to start session: - no session ID returned");
			}
		});
		#if (target.threaded )
		});
		#end
	}

	/**
	 * This function stops any active sessions.
	 * You should make sure to do this before the application closes!
	 */
	public static function StopSession():Void
	{
		if (Status != CCStatus.INITIALIZED)
		{
			return;
		}

		if (SessionStatus != CCStatus.INITIALIZED)
		{
			return;
		}

		clear();
		sendData(HTTP_URL,"gameSession.stopSession", Json.stringify({gameSessionID: sessionID}), (err)->{
			throw("Failed to stop session: " + err);
		}, (r)->{	
			SessionStatus = CCStatus.NONE;
			var response = Json.parse(r);
			if (verbose)
				trace("Crowd Control Session Stop Response: " + response);
		});
	}

	private static function sendData(URL:String, Action:String, Data:String, OnError:String->Void, OnData:String->Void):Void
	{
		#if (target.threaded )
		sys.thread.Thread.create(() -> {
		#end
		var url:String = URL + Action + "?ref=" + Std.string(haxe.Timer.stamp()*1000);
		var h:Http = new Http(url);
		h.setHeader("Authorization", "cc-auth-token " + authToken);
		h.onError = OnError;
		h.onData = OnData;

		h.setPostData(Data);

		h.request(true);
		#if (target.threaded )
		});
		#end
	}

	private static function processEffects():Void
	{
		if (Paused || Status != CCStatus.INITIALIZED || SessionStatus != CCStatus.INITIALIZED)
			return;

		var effect:Effect;
		for (eff in EffectQueue)
		{
			if (eff.effectStatus == EffectStatus.PENDING)
			{
				effect = Effects.get(eff.effectID);
				if (effect.onStart())
				{
					if (eff.duration > 0)
					{
						eff.effectStatus = EffectStatus.STARTED;
						
						sendStatus(TIMED_BEGIN, eff.requestID);
					}
					else
					{
						eff.effectStatus = EffectStatus.SUCCESS;
						
						sendStatus(SUCCESS, eff.requestID);
					}
				}
				else
				{
					eff.tries++;
					if (eff.tries >= MAX_TRIES)
					{
						eff.effectStatus = EffectStatus.FAILED;
						
						sendStatus(FAIL_TEMPORARY, eff.requestID);

					}
				}
			}
			else if (eff.effectStatus == EffectStatus.STARTED)
			{
				eff.duration-=elapsed;
				if (eff.duration <= 0)
				{
					eff.effectStatus = EffectStatus.ENDING;
					eff.tries = 0;
				}
					
				
			}
			else if (eff.effectStatus == EffectStatus.ENDING)
			{
				effect = Effects.get(eff.effectID);
				if (effect.onEnd())
				{
					
					eff.effectStatus = EffectStatus.SUCCESS;

					sendStatus(TIMED_END, eff.requestID);
					
				}
				else
				{
					eff.tries++;
					if (eff.tries >= MAX_TRIES)
					{
						eff.effectStatus = EffectStatus.FAILED;

						sendStatus(FAIL_TEMPORARY, eff.requestID);
					}
				}
			}
		}

		EffectQueue = EffectQueue.filter(function(eff:EffectRequest):Bool
		{
			return eff.effectStatus == EffectStatus.PENDING ||  eff.effectStatus == EffectStatus.STARTED || eff.effectStatus == EffectStatus.ENDING;
		});
	}

	/**
	 * Clears the effect queue and sends a FAIL_TEMPORARY response to all pending effects.
	 * This should be called when a level ends or when it makes sense to wipe out all of the effects.
	 * Not for paused games, etc.
	 */
	public static function clear():Void
	{
		for (e in EffectQueue)
		{
			sendStatus(FAIL_TEMPORARY, e.requestID);
		}
		EffectQueue = [];
	}

	private static function subscribe():Void
	{
		ws.sendString(Json.stringify({
			action: "subscribe",
			data: Json.stringify({topics: ['pub/' + user.ccUID]})
		}));
	}

	private static function sendWhoAmI():Void
	{
		ws.sendString(Json.stringify({
			action: "whoami",
		}));
	}

	private static function set_Paused(Value:Bool):Bool
	{
		if (Value == Paused)
			return Paused;

		Paused = Value;

		if (Paused)
		{
			for( e in EffectQueue)
			{
				if (e.duration > 0 && e.effectStatus != FAILED)
				{
					sendStatus(TIMED_PAUSE, e.requestID);	
				}
			}
		}
		else
		{
			for( e in EffectQueue)
			{
				if (e.duration > 0 && e.effectStatus != FAILED)
				{
					sendStatus(TIMED_RESUME, e.requestID);	
				}
			}
		}

		return Paused;
	}

	private static function sendStatus(Status:ResponseStatus, EffectID:String):Void
	{
		var randID:String  = Uuid.v4();
		var responseData:String = Json.stringify({
			token: authToken,
			call: {
				method: "effectResponse",
				args: [{
					request: EffectID,
					id: randID,
					stamp: Date.now().getTime() ,
					status: Status,
					message:""
				}],
				id : randID,
				type:"call"
			}
		});

		var responseBody:String = Json.stringify({
			action: "rpc",
			data: responseData
		});

		ws.sendString(responseBody);

	}

	/**
	 * Opens a web page, by default a new tab or window. If the URL does not
	 * already start with `"http://"` or `"https://"`, it gets added automatically.
	 *
	 * @param   URL      The address of the web page.
	 * @param   Target   `"_blank"`, `"_self"`, `"_parent"` or `"_top"`
	 */
	public static inline function openURL(URL:String, Target:String = "_blank"):Void
	{
		var prefix:String = "";
		// if the URL does not already start with "http://" or "https://", add it.
		if (!~/^https?:\/\//.match(URL))
			prefix = "http://";
		#if js
		js.Browser.window.open(prefix + URL, Target);
		#else
		Sys.command("start", [prefix + URL]);
		#end
	}

	/**
	 * Adds a function to the list of effects that can be triggered by Crowd Control.
	 * Note: duplicate effect ids will be ovewritten.
	 * 
	 * @param effectID		The ID of the effect. This is what you will use to trigger the effect.
	 * @param onStart 		The function that will be called when the effect is triggered. 
	 * 						This function should not take any parameters, and return a TRUE if the effect happened 
	 * 						successfully, otherwise FALSE
	 * @param onEnd 		The function that will be called when the effect is ended. It should not take any
	 * 						parameters, and return TRUE if the effect ended successfully, otherwise FALSE.
	 */
	public static function AddEffect(effectID:String, onStart:Void->Bool, ?onEnd:Void->Bool):Void
	{
		Effects.set(effectID, new Effect(effectID, onStart, onEnd));
	}

	/**
	 * Remove an effect from the list of effects that can be triggered by Crowd Control.
	 * 
	 * @param effectID 
	 */
	public static function RemoveEffect(effectID:String):Void
	{
		Effects.remove(effectID);
	}
}


class Effect {

	public var name(default, null):String;
	public var onStart(default, null):Void->Bool;
	public var onEnd(default, null):Void->Bool;

	public function new(name:String, onStart:Void->Bool, onEnd:Void->Bool)
	{
		this.name = name;
		this.onStart = onStart;
		this.onEnd = onEnd;
	}

}

class User
{
	public var originID(default, null):String="";
	public var profileType(default, null):UserIDType = UserIDType.TWITCH;
	public var ccUID(default, null):String="";
	public var name(default, null):String="";

	public function new(originID:String, profileType:UserIDType, ccUID:String, name:String)
	{
		this.originID = originID;
		this.profileType = profileType;
		this.ccUID = ccUID;
		this.name = name;
	}

	public function toString():String
	{
		return "User(" + originID + ", " + profileType + ", " + ccUID + ", " + name + ")";
	}
}

@:enum abstract PacketType(Int)
{
	var CONNECT = 0;
	var DISCONNECT = 1;
	var EVENT = 2;
	var ACK = 3;
	var CONNECT_ERROR = 4;
	var BINARY_EVENT = 5;
	var BINARY_ACK = 6;
}

@:enum abstract UserIDType(String)
{
	var TWITCH = "twitch";
	var DISCORD = "discord";
	var YOUTUBE = "youtube";
}

@:enum abstract CCStatus(Int)
{
	var NONE = 0;
	var INITIALIZING = 1;
	var INITIALIZED = 2;
}

class EffectRequest
{
	public var effectID(default, null):String="";
	public var effectStatus:EffectStatus= EffectStatus.PENDING;
	public var tries:Int =0 ;
	public var duration:Float=0;
	public var requestID:String = "";

	public function new(effectID:String, RequestID:String, Duration:Float = 0)
	{
		this.effectID = effectID;
		this.effectStatus = EffectStatus.PENDING;
		this.tries = 0;
		this.duration = Duration;
		this.requestID = RequestID;
	}
}

@:enum abstract EffectStatus(Int)
{
	var PENDING = 0;
	var SUCCESS = 1;
	var FAILED = 2;
	var STARTED= 3;
	var ENDED = 4;
	var ENDING = 5;
}

@:enum abstract ResponseStatus(String)
{
	var SUCCESS = "success";
	var TIMED_BEGIN = "timedBegin";
	var TIMED_END = "timedEnd";
	var TIMED_PAUSE	= "timedPause";
	var TIMED_RESUME = "timedResume";
	var FAIL_TEMPORARY = "failTemporary";
	var FAIL_PERMANENT = "failPermanent";

}
