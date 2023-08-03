package crowdcontrol;

import haxe.Http;
import haxe.Json;
import haxe.Timer;
import haxe.net.WebSocket;
import jwt.JWT;
import openfl.Lib;
import openfl.net.URLRequest;

class CrowdControl
{
	private static inline var SOCKET_URL:String = "wss://pubsub.crowdcontrol.live";

	private static inline var AUTH_URL:String = "https://auth.crowdcontrol.live/?connectionID=";

	private static var ccUID:String = "";

	public static var Status:CCStatus;

	private static var timer:Timer;

	private static var ws:WebSocket;

	private static var user:User;

	private static var GamePack:String = "";

	/* While Paused, the Crowd Control System will not process any effects - they will just keep getting put into the queue. */
	public static var Paused:Bool = true;

	private static var EffectQueue:Array<EffectRequest> = [];

	private static var Effects:Map<String, Void->Bool> = [];

	private static var MAX_TRIES:Int = 5;
	private static var MAX_TIME:Int = 60000;

	/**
	 * Call this to initialize the Crowd Control System
	 * 
	 * @param GamePackID 		The ID of the game pack you are using.
	 */
	public static function Initialize(GamePackID:String):Void
	{
		if (Status != CCStatus.NONE)
			return;

		if (GamePackID == "")
		{
			throw("GamePackID cannot be empty");
			return;
		}

		GamePack = GamePackID;

		ws = WebSocket.create(SOCKET_URL, null, null, true);

		ws.onopen = function()
		{
			trace('open!');

			sendWhoAmI();
		}

		ws.onmessageString = function(message)
		{
			var response = Json.parse(message);

			trace(response);

			if (response.type == "whoami")
			{
				var connectionID = response.payload.connectionID;

				openURL(AUTH_URL + connectionID, "_blank");
			}
			else if (response.type == "login-success")
			{
				var authToken = response.payload.token;

				var userData:Dynamic = JWT.extract(authToken);

				user = new User(userData.originID, userData.profileType, userData.ccUID, userData.name);

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
					EffectQueue.push(new EffectRequest(response.payload.effect.effectID));
				}
			}
		};

		timer = new Timer(100);
		timer.run = function()
		{
			ws.process();
			processEffects();
		};
	}

	private static function processEffects():Void
	{
		if (Paused)
			return;

		for (eff in EffectQueue)
		{
			if (eff.effectStatus == EffectStatus.PENDING)
			{
				if (Effects.get(eff.effectID)())
				{
					eff.effectStatus = EffectStatus.SUCCESS;
				}
				else
				{
					eff.tries++;
					if (eff.tries >= MAX_TRIES)
					{
						eff.effectStatus = EffectStatus.FAILED;
					}
				}
			}
		}

		// remove all effects that have EffectStatus.SUCCESS or EffectStatus.FAILED
		EffectQueue = EffectQueue.filter(function(eff:EffectRequest):Bool
		{
			return eff.effectStatus == EffectStatus.PENDING;
		});
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
		Lib.getURL(new URLRequest(prefix + URL), Target);
	}

	/**
	 * Adds a function to the list of effects that can be triggered by Crowd Control.
	 * Note: duplicate effect ids will be ovewritten.
	 * 
	 * @param effectID		The ID of the effect. This is what you will use to trigger the effect.
	 * @param effect 		The function that will be called when the effect is triggered. 
	 * 						This function should not take any parameters, but return a TRUE if the 
	 * 						effect happened successfully, otherwise FALSE
	 */
	public static function AddEffect(effectID:String, effect:Void->Bool):Void
	{
		Effects.set(effectID, effect);
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

class User
{
	public var originID(default, null):String;
	public var profileType(default, null):UserIDType;
	public var ccUID(default, null):String;
	public var name(default, null):String;

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
}

@:enum abstract CCStatus(Int)
{
	var NONE = 0;
	var INITIALIZING = 1;
	var INITIALIZED = 2;
}

class EffectRequest
{
	public var effectID(default, null):String;
	public var effectStatus:EffectStatus;
	public var tries:Int;

	public function new(effectID:String)
	{
		this.effectID = effectID;
		this.effectStatus = EffectStatus.PENDING;
		this.tries = 0;
	}
}

@:enum abstract EffectStatus(Int)
{
	var PENDING = 0;
	var SUCCESS = 1;
	var FAILED = 2;
}
