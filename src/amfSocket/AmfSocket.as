package amfSocket {
import amfSocket.events.AmfSocketEvent;

import flash.events.Event;
import flash.events.EventDispatcher;
import flash.events.IOErrorEvent;
import flash.events.ProgressEvent;
import flash.events.SecurityErrorEvent;
import flash.net.Socket;
import flash.utils.ByteArray;

public class AmfSocket extends EventDispatcher {
    public static const CHARSET_LATIN1:String = 'iso-8859-1';
    public static const FORMAT_AMF3:int = 1;
    public static const FORMAT_BERT:int = 2;

    //
    // Instance variables.
    //

    private static var _logger:Object;

    public static function get logger():Object {
        return _logger;
    }

    public static function set logger(value:Object):void {
        _logger = value;
    }

    public function AmfSocket(host:String = null, port:int = 0, compress:Boolean = false, format:int = FORMAT_AMF3) {
        _host = host;
        _port = port;
        _compress = compress;
        _format = format;
        if (_format == FORMAT_BERT) {
            _bert = new Bert();
        }
    }

    private var _format:int;
    private var _bert:Bert;
    private var _host:String = null;
    private var _port:int = 0;
    private var _socket:Socket = null;
    private var _objectLength:int = -1;
    private var _buffer:ByteArray = new ByteArray();
    private var _compress:Boolean = false;
    private var _connecting:Boolean = false;
    //
    // Constructor.
    //

    public function get connected():Boolean {
        if (!_socket || !_socket.connected)
            return false;
        else
            return true;
    }

    //
    // Public methods.
    //

    public function log(message:String):void {
        var foo:Object = _logger;

        if (!_logger)
            return;

        _logger.debug(message);
    }

    public function connect():void {
        if (connected)
            throw new Error('Can not connect an already connected socket.');

        if (_connecting)
            return;
        _connecting = true;
        _socket = new Socket();
        addEventListeners();
        _socket.connect(_host, _port);
    }

    public function disconnect():void {
        if (_socket) {
            removeEventListeners();

            if (_socket.connected)
                _socket.close();
        }

        _socket = null;
    }

    public function sendObject(object:Object):void {
        if (!connected) {
            reconnect(object);
        }

        if (_format == FORMAT_AMF3) {
            var byteArray:ByteArray = encodeObject(object);
            _socket.writeUnsignedInt(byteArray.length);
            _socket.writeBytes(byteArray);
            _socket.flush();
        } else {
            _bert.writePacket(object, _socket);
            _socket.flush();
        }
    }

    private function reconnect(object:Object, times:int = 3):void {
        if (times > 0) {
            throw new Error('Can not send over a non-connected socket.');
        }
        connect();
        var resend:Function = function ():void {
            _socket.removeEventListener(Event.CONNECT, resend);
            if (!connected) {
                reconnect(object, times - 1);
            } else {
                sendObject(object);
            }
        };
        _socket.addEventListener(Event.CONNECT, resend);
    }

    //
    // Private methods.
    //

    private function addEventListeners():void {
        if (!_socket)
            throw new Error('Can not add event listeners to a null socket.');

        _socket.addEventListener(Event.CONNECT, socket_connect);
        _socket.addEventListener(Event.CLOSE, socket_disconnect);
        _socket.addEventListener(IOErrorEvent.IO_ERROR, socket_ioError);
        _socket.addEventListener(SecurityErrorEvent.SECURITY_ERROR, socket_securityError);
        _socket.addEventListener(ProgressEvent.SOCKET_DATA, socket_socketData);
    }

    private function removeEventListeners():void {
        if (!_socket)
            throw new Error('Can not remove event listeners from a null socket.');

        _socket.removeEventListener(Event.CONNECT, socket_connect);
        _socket.removeEventListener(Event.CLOSE, socket_disconnect);
        _socket.removeEventListener(IOErrorEvent.IO_ERROR, socket_ioError);
        _socket.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, socket_securityError);
        _socket.removeEventListener(ProgressEvent.SOCKET_DATA, socket_socketData);
    }

    private function encodeObject(object:*):ByteArray {
        var byteArray:ByteArray = new ByteArray();
        byteArray.writeObject(object);
        if (_compress) {
            byteArray.compress();
        }

        return byteArray;
    }

    //
    // Event handlers.
    //

    private function readBufferedObject():* {
        _buffer.position = 0;

        if (_buffer.length >= 4) {
            var payloadSize:int = _buffer.readUnsignedInt();

            if (_buffer.length >= payloadSize + 4) {
//          if (_compress) {
//            _buffer.uncompress();
//          }
                var object:* = null;
                if (_format == FORMAT_AMF3) {
                    object = _buffer.readObject();
                } else {
                    object = _bert.read(_buffer, payloadSize);
                }
                shiftBuffer(4 + payloadSize);

                return object;
            }

            return null;
        }

        return null;
    }

    private function shiftBuffer(count:int):void {
        var tmpBuffer:ByteArray = new ByteArray();

        _buffer.position = count;
        _buffer.readBytes(tmpBuffer);
        _buffer = tmpBuffer;
    }

    private function socket_connect(event:Event):void {
        log('Connected.');
        _connecting = false;
        dispatchEvent(new AmfSocketEvent(AmfSocketEvent.CONNECTED));
    }

    private function socket_disconnect(event:Event):void {
        log('Disconnected.');

        removeEventListeners();
        _socket = null;

        dispatchEvent(new AmfSocketEvent(AmfSocketEvent.DISCONNECTED));
    }

    private function socket_ioError(event:IOErrorEvent):void {
        log('IO Error.');

        dispatchEvent(new AmfSocketEvent(AmfSocketEvent.IO_ERROR));
    }

    private function socket_securityError(event:SecurityErrorEvent):void {
        log('Security Error.');

        dispatchEvent(new AmfSocketEvent(AmfSocketEvent.SECURITY_ERROR));
    }

    private function socket_socketData(event:ProgressEvent):void {
        log('Received Data. bytesAvailable=' + _socket.bytesAvailable);

        // Append socket data to buffer.
        _buffer.position = 0;
        _socket.readBytes(_buffer, _buffer.length, _socket.bytesAvailable);

        // Process any buffered objects.
        var object:* = readBufferedObject();
        while (object) {
            log('Received Object.');
            dispatchEvent(new AmfSocketEvent(AmfSocketEvent.RECEIVED_OBJECT, object));
            object = readBufferedObject();
        }
    }
}
}