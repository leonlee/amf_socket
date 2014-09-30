package amfSocket {
import amfSocket.events.AmfSocketEvent;

import flash.events.Event;
import flash.events.EventDispatcher;
import flash.events.IOErrorEvent;
import flash.events.ProgressEvent;
import flash.events.SecurityErrorEvent;
import flash.net.ObjectEncoding;
import flash.net.Socket;
import flash.utils.ByteArray;
import flash.utils.CompressionAlgorithm;
import flash.utils.Endian;

import org.as3commons.logging.api.ILogger;
import org.as3commons.logging.api.getLogger;

public class AmfSocket extends EventDispatcher {
    public static const FORMAT_AMF3:int = 1;
    public static const FORMAT_MSGPACK:int = 2;
    private static const _logger:ILogger = getLogger(AmfSocket);

    public static function log(message:String):void {
        if (!_logger) {
            return;
        }
        _logger.debug(message);
    }

    public function AmfSocket(host:String = null, port:int = 0, compress:Boolean = false, format:int = FORMAT_AMF3) {
        _host = host;
        _port = port;
        _compress = compress;
        _format = format;
        if (_format == FORMAT_MSGPACK) {
            throw new Error("not implemented msgpack");
        }
    }

    private var _format:int;
    private var _host:String = null;
    private var _port:int = 0;
    private var _socket:Socket = null;
    private var _buffer:ByteArray = new ByteArray();

    //
    // Constructor.
    //
    private var _compress:Boolean = false;

    //
    // Public methods.
    //

    public function get connected():Boolean {
        if (!_socket || !_socket.connected)
            return false;
        else
            return true;
    }

    public function connect():void {
        if (connected)
            throw new Error('Can not connect an already connected socket.');

        _socket = new Socket();
        addEventListeners();
        _socket.endian = Endian.BIG_ENDIAN;
        _socket.objectEncoding = ObjectEncoding.AMF3;
        _socket.connect(_host, _port);
    }

    public function disconnect():void {
        if (_socket) {
            if (_socket.connected)
                _socket.close();
            removeEventListeners();
        }

        _socket = null;
    }

    public function sendObject(object:Object):void {
        if (!connected)
            throw new Error('Can not send over a non-connected socket.');

        if (_format == FORMAT_AMF3) {
            var byteArray:ByteArray = encodeObject(object);
            _socket.writeUnsignedInt(byteArray.length);
            _socket.writeBytes(byteArray);
            _socket.flush();
        } else if (_format == FORMAT_MSGPACK) {
            throw new Error("not implemented msgpack");
        }
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
                var objectBuffer:ByteArray = null;
                if (_compress) {
                    objectBuffer = new ByteArray();
                    objectBuffer.writeBytes(_buffer, _buffer.position);
                    objectBuffer.uncompress(CompressionAlgorithm.ZLIB);
                } else {
                    objectBuffer = _buffer;
                }

                var object:* = null;
                if (_format == FORMAT_AMF3) {
                    object = objectBuffer.readObject();
                } else if (_format == FORMAT_MSGPACK) {
                    throw new Error("not implemented msgpack");
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
//        log('Received Data. bytesAvailable=' + _socket.bytesAvailable);

        // Append socket data to buffer.
        _buffer.position = 0;
        _socket.readBytes(_buffer, _buffer.length, _socket.bytesAvailable);

        // Process any buffered objects.
        var object:* = readBufferedObject();
        while (object) {
//            log('Received Object.');
            dispatchEvent(new AmfSocketEvent(AmfSocketEvent.RECEIVED_OBJECT, object));
            object = readBufferedObject();
        }
    }
}
}