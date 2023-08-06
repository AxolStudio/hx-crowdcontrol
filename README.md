# hx-crowdcontrol

[![GitHub license](https://img.shields.io/badge/license-BSD-blue.svg?style=flat-square)](https://raw.githubusercontent.com/AxolStudio/hx-crowdcontrol/master/LICENSE)

A [Crowd Control 2.0](https://crowdcontrol.live/) library for native [Haxe](https://haxe.org/).

**⚠️ It is important to mention that you will need to contact Crowd Control to completely setup your game for it to work with this library.**

## Features

* Easily connects to Crowd Control 2.0
* Functions to start/stop Sessions
* Easily add 2 kinds of effects that can be triggered by Crowd Control:
  + One-off effects, like 'spawn an enemy', or 'give the player health'
  + Timed effects, like '30 seconds of invincibility'

## Usage

The library is designed to hook into your game with minimal effort.

### Initializing

```haxe
CrowdControl.Initialize('MyGamePack');
```

Before you can start a session or start receiving effect requests, you must initialize the library with your Game Pack ID.

When the library is being intialized, it will try to authenticate the user - if it cannot find a valid authentication token, it will open a browser window to where the user can authenticate.

`CrowdControl.Status` will be set to `CCStatus.INITIALIZED` once the library has been successfully initialized.

### Adding effects

You use the `CrowdControl.AddEffect` method to add effects to your game.

#### One-off effects

```haxe
CrowdControl.AddEffect('spawn_enemy', ()->{
   
   return PlayState.spawnEnemy();

});
```

To add an effect that triggers once per request, such as spawning an enemy, or giving the player an item, etc, you simply pass 2 arguments to `AddEffect`:

`effectID`
: The ID of the effect, as defined in your Crowd Control Game Pack.

`onStart`
: A function that is called when the effect is triggered. This function should return `true` if the effect was successfully started, or `false` if it failed to start.

#### Timed effects

```haxe
CrowdControl.AddEffect('invincibility', ()->{
   
   PlayState.player.invincible = true;
   return true;

}, ()->{
    
    PlayState.player.invincible = false;
    return true;
    
});
```

To add a timed effect, one that lasts for a duration, pass a third argument to `AddEffect`:

`onEnd`
: A function that is called when the effect ends. This function should return `true` if the effect was successfully ended, or `false` if it failed to end.

### Starting a session

```haxe
CrowdControl.StartSession();
```

Once you have added all of your effects, you can start a session. This will connect to Crowd Control and start receiving effect requests. The library must be initialized before you can start a session.

`CrowdControl.SessionStatus` will be set to `CCStatus.INITIALIZED` once the session has been successfully started.

### Stopping a session

```haxe
CrowdControl.StopSession();
```

You can stop a session at any time by calling `StopSession`. This will disconnect from Crowd Control and stop receiving effect requests.

You *should* make sure to do this before your application exits!

### Pausing

```haxe
CrowdControl.Paused = true;
```

Effect processing will be paused by default. You can unpause it by setting `CrowdControl.Paused` to `false`.

Once a session is started, effect requests will be queued in the order they were recieved.

While unpaused, the library will process requests in order.

When you pause the library, any timed effects that are currently running will be paused until you unpause.

The ideal scenario is to leave the library paused while in menus, and unpause once the game starts. Pause anytime a cut-scene or a pause menu is opened, and unpause once you return to gameplay. This means that if a user has requested an effect like "spawn enemy" the game won't try to spawn the enemy and timed effects, like "30 seconds of invincibility" will not run out when the player is in menus.

Specifying the proper places to pause/unpause your game is paramount to making sure that the user's requests are processed correctly.

### Interaction URL

```haxe
trace(CrowdControl.InteractionURL);
```

Users can interact with your game through the Twitch Plugin, or, through the streamer's unique Interaction Portal. Once the library is initialized, you can get the URL to the Interaction Portal by accessing `CrowdControl.InteractionURL`.

It would be useful to display this somewhere, perhaps in a dedicated Crowd Control interface, so the streamer can easily see it and copy/paste it elsewhere for their users to access.

### Clearing effects

```haxe
CrowdControl.clear();
```

You can clear all effects by calling `CrowdControl.clear()`. This will remove all effects that have been queued and have not finished yet, and will send the `FAILED_TEMPORARY` message back to Crowd Control for each effect.
This should really only be used when a level or the game ends completely and you don't want timed effects or queued effects to sit and wait in the queue.

### Debugging

```haxe
CrowdControl.verbose = true;
```

If you want to see a lot more detail on the responses from Crowd Controls servers, you can turn verbose mode on. This will print out a lot of information to the console, so it is recommended to only use this when debugging.

## Example Usage

To demonstrate a simple use case, here are some of the modifications made to the [HaxeFlixel demo project *mode*](https://haxeflixel.com/demos/Mode/) to add Crowd Control support.

Main.hx
```haxe
package;

import haxe.Timer;
import crowdcontrol.CrowdControl;
import flixel.FlxG;
import flixel.FlxGame;
import flixel.math.FlxPoint;
import openfl.Lib;
import openfl.display.Sprite;

class Main extends Sprite
{
	public static var PlayState:PlayState;

	public function new()
	{
		super();
		addChild(new FlxGame(320, 240, MenuState));

      // NEW for Crowd Control ========================

      // enable versbose mode for debugging
		CrowdControl.verbose = true; 

      // Initialize the library with your Game Pack ID - in this case, 
      // we are using the Castlevania 3 Game Pack (because there is no mode 
      // game pack and we're just testing)
		CrowdControl.Initialize("Castlevania3");

      // Add a one-off effect that will spawn an enemy near the player when a 
      // user buys the "Increase Time by 100" effect called "timeup"
		CrowdControl.AddEffect("timeup", () ->
		{
			var e:Enemy = PlayState._enemies.recycle(Enemy.new);
			var mp:FlxPoint = PlayState._player.getMidpoint();
			if (e != null)
				e.init(Std.int(mp.x + (FlxG.random.float(10, 50) * FlxG.random.sign())), Std.int(mp.y + (FlxG.random.float(10, 50) * FlxG.random.sign())),
					PlayState._enemyBullets, PlayState._littleGibs, PlayState._player);
			return e != null; // return true if the enemy was spawned successfully
		});

      // Add a timed effect that will make the player invulnerable for 30 seconds when
      // a user buys the "Invulnerability" effect called "invul"
		CrowdControl.AddEffect("invul", () ->
		{
			PlayState._player.invulnerable = true;
			return true;
		}, () ->
			{
				PlayState._player.invulnerable = false;
				return true;
      });

      // Add a timer to check for the library to be initialized and then automatically
      // start a new session - in real practice you should give the player an interface
      // to start/stop the session and show their interaction URL, but this is just a demo
		var timer:Timer = new Timer(500);
		timer.run = () ->
		{
			if (CrowdControl.Status == INITIALIZED && CrowdControl.SessionStatus == NONE)
			{
				CrowdControl.StartSession();
				timer.stop();
			}
		};

      // Stop the session when the application exits
		Lib.application.onExit.add((_) ->
		{
			CrowdControl.StopSession();
		});

      // ========================================================
	}
}
```

Note: Some of the changes that are not shown include: 
  * adding `CrowdControl.paused` to various places in the code to pause/unpause the library. You want to make sure that it is only unpaused during the actual gameplay, and paused when on the main menu or when the demo/eyecatch is playing.
  * setting `Main.PlayState` to `this` when the `PlayState` is initialized to it can be accessed from other classes. 
  * the places where `public` was added to variables and functions to expose them more easily for our purposes.
  * the `Player.invulnerable` setter which turns the player red when `true` and back again on `false`, and the logic in `Player.hurt` to check for `invulnerable`.

## Testing

1. Run your game project and after calling `CrowdControl.Initialize` a browser window should open to allow you to sign in to Crowd Control via your Twitch, Discord, or YouTube account(if you are running your game in a browser, it may block the tab from opening, so you may need to allow popups).
2. Open a new browser tab to your Crowd Control Interaction Portal (you can find the URL by calling `CrowdControl.InteractionURL` after the library has been initialized and it will be traced to the console).
3. Login to the Portal with the same account you authenticated in-game.
4. You can now order effects in the Portal and test them out in your game!

# Change Log

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

### 1.1.0
#### Added 
 - `CrowdControl.InteractionURL`
 - Threading for effect processing

### 1.0.0
#### Added
- Original release of all the core functionality.
