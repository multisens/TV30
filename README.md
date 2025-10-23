# TV 3.0 AoP Experimentation

![Node Version](https://img.shields.io/badge/Node.js-23.11.0-blueviolet?logo=nodedotjs)  ![MQTT](https://img.shields.io/badge/MQTT-blueviolet?logo=mqtt)

The **TV 3.0 AoP Experimentation** project provides an evironment for experimenting with TV 3.0 AoP services. The environment is designed to be extensible such that developers can easily create/extend its functionalities.


# Features

* Distributed implementation of TV 3.0 components in a microservices fashion
* MQTT-based


# Architecture

```mermaid
---
config:
  look: handDrawn
  theme: neutral
---
block-beta
   columns 5
   TV["AoP\n(Node.js)"] space B["Broker\n(MQTT)"] space WS["TV 3.0 WebServices\n(Node.js)"]
   TV --> B
   B --> TV
   WS --> B
   B --> WS
   space:5
   APP["Broadcaster Apps\n(Node.js)"] space NCL["TV 3.0 Ginga-NCL"]
   B --> NCL
   NCL --> B
   TV --> APP
   APP --> B
   B --> APP
```

# Dependencies

* Mosquitto MQTT Broker
* Node JS
* [PM2](https://pm2.keymetrics.io)
* [NW.js](https://nwjs.io)
* [FFmpeg](https://ffmpeg.org)


# Execution

Components managed by PM2.
```$ pm2 start ecosystem.config.js```