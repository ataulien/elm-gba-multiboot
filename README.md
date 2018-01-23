# elm-gba-multiboot

## The why
This is a project I worked on for university. It is supposed to be about bringing the functional programming language "elm" to the world of microcontrollers. Elm is throught to be a language for the web and thus compiles to JavaScript.

Here are some facts:
 1. There is support for NodeJS in elm, but since there is no NodeJS on embedded systems, I had to disect the generated file manually. 
 1. The generated Javascript-file is about 5000 lines long. I've tried multiple embedded JS-projects (Espruino, Duktape, JerryScript) and none could handle that large file on an STM32F4 with 192k RAM.
 2. I've compiled my attempt with Duktape for Linux to run on my desktop-computer - worked fine.
 3. Running the closure-compiler on the generated file to reduce it's size didn't help either.
 
In conclusion: I didn't get elm to run on an embedded system. A RaspberryPi would have worked, but at that point I kinda gave up.
 
There are some other promising projects which allow to run some JS-Code via NodeJS on a PC and only send small commands to a connected Arduino, for example. One of those projects is "Johnny-Five", and I had it running quite fast. From the idea to a blinking LED using NodeJS and Elm in under half an hour!

But a blinking LED would be too simple, right? 

## The what

Entering: The Gameboy Advance!

I played around with the GBAs multiboot-capability (that is: upload a small rom using the Link-Cable) before, but couldn't get it to work. I still had my modified GBA laying around... (which I had no cables for, so it looks kind of demolished now since I had to solder some directly to the board and broke the casing while doing so)

![My GBA](https://github.com/ataulien/elm-gba-multiboot/blob/master/media/the-better-link-cable.jpg)

Since the Gameboy uses the simple SPI-Protocol for communication, which is a widely adopted industry standard, and the Arduino has a library for that, I thought: "Why not? That would be fun!".

A small (kinda-working) prototype in C later: Time to port this thing to johnny-five and elm!

... too bad, there is no SPI-Support in Johnny-five.

## The how

My first attempt had the Arduino just being a proxy, getting the SPI-commands from the serial-connection and sending the contents straight to the Gameboy. Couldn't get that to work, unfortunately.

I ended up coding the whole protocol in C on the arduino, using an extremly simple custom serial protocol to talk to NodeJS and Elm on the PC-side of things.

![Elm!](https://github.com/ataulien/elm-gba-multiboot/blob/master/media/yes-i-took-a-screenshot-with-my-phone--looks-cool-doesnt-it.jpg)

So, to upload a ROM to the Gameboy, one would have Elm send the ROM-Data over a serial-connection to the arduino, which then talks to the gameboy, encrypts the data and sends it further down the line. 

![Oh god it finally works.](https://github.com/ataulien/elm-gba-multiboot/blob/master/media/it-finally-works---im-freeeee.jpg)

The Elm-Program basically resembles a state machine and uses ports to talk to NodeJS, which I tried to use as little as possible.

## How did Elm hold up to the task?

I guess writing the PC-side in pure JS, rather than Elm would have made the code a lot shorter and easier to read. I'm still learning Elm though, so maybe there is some cool feature which would get rid of like 80% of the complexity.

My main issues with the elm-version is the obfuscated control-flow. But I probably just suck at writing Elm :)

There isn't really going on much in the Elm-program, which makes use of the features that make functional programming shine. I wish I had time to move the whole protocoll over to Elm, but with the like 4 failed attempts on getting Elm to run on a microcontroller, time was running out.

# Bulding

If someone really wants to try this: (makes little sense without the arduino hooked up to the gameboy)

```sh
mkdir node_modules
elm-make elm-flash.elm --output node_modules/elm-flash.js
```

# Running

```sh
node flash.js /dev/ttyACM0 gbahello_mb.gba
```
