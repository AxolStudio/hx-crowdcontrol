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

### Debugging

```haxe
CrowdControl.verbose = true;
```

If you want to see a lot more detail on the responses from Crowd Controls servers, you can turn verbose mode on. This will print out a lot of information to the console, so it is recommended to only use this when debugging.

# Change Log

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

### 1.0.0
#### Added
- Original release of all the core functionality.
