# AMF Socket - Actionscript

AMF Socket is a bi-directional RPC system for Adobe Flash (Actionscript) programs.
This library aims to make high quality (and free) RPC accessible to all of the Flash platforms (web, mobile, and desktop).
Using this library you can easily add event driven network functionality to your Flash applications without having to deal with the low level details.
High performance and low latency is accomplished through the use of persistent TCP/IP sockets and Flash's native serialization format (AMF).

## Example (lower level AMF socket layer)

    var sock:AmfSocket = new AmfSocket('localhost', 9000);
    sock.addEventListener(AmfSocketEvent.CONNECTED, function(event:AmfSocketEvent):void {
      trace('connected');
      sock.sendObject({'some_key': 'some_value'});
    });

    sock.addEventListener(AmfSocketEvent.DISCONNECTED, function(event:AmfSocketEvent):void {
      trace('disconnected');
    });

    sock.addEventListener(AmfSocketEvent.IO_ERROR, function(event:AmfSocketEvent):void {
      trace('io error');
    });

    sock.addEventListener(AmfSocketEvent.RECEIVED_OBJECT, function(event:AmfSocketEvent):void {
      trace('received object');
    });

    sock.addEventListener(AmfSocketEvent.SECURITY_ERROR, function(event:AmfSocketEvent):void {
      trace('security error');
    });

    sock.connect();

## Example (Higher level RPC layer)

    TODO: Coming soon.

## Server Implementations

* [Ruby](https://github.com/chadrem/amf_socket_ruby)

## Wire Protocol

Each message has a 4 byte header followed by a variable length payload encoded in AMF verison 3.
The header contains a single unsigned int that indicates the length (in bytes) of the payload.
All messages use big-endian byte ordering.

For more information on AMF: [http://en.wikipedia.org/wiki/Action_Message_Format](http://en.wikipedia.org/wiki/Action_Message_Format)

## Copyright

Copyright (c) 2012 Chad Remesch. See LICENSE.txt for details.
