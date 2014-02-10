package amfSocket {
import amfSocket.events.AmfSocketEvent;
import amfSocket.events.RpcManagerEvent;

import flash.events.EventDispatcher;
import flash.events.TimerEvent;
import flash.utils.Dictionary;
import flash.utils.Timer;

import org.as3commons.logging.api.ILogger;
import org.as3commons.logging.api.getLogger;

public class RpcManager extends EventDispatcher {
    private static const logger:ILogger = getLogger(RpcManager);
    //
    // Constructor.
    //

    public function RpcManager(host:String, port:int, options:Object = null) {
        super();

        _host = host;
        _port = port;
        _options = options;

        if (options == null)
            options = {};

        if (options['autoReconnect'] === null)
            options['autoReconnect'] = 3;

        if (options['autoReconnect'] !== null) {
            _reconnectTimer = new Timer(3000, options['autoReconnect']);
            _reconnectTimer.addEventListener(TimerEvent.TIMER, reconnectTimer_timer);
            _reconnectTimer.start();
        }

        if (options['reconnectHandler'] instanceof Function) {
            _reconnectHandler = options['reconnectHandler'];
        }

        _compress = options['compress'] != null && options['compress'] != false;
        _format = options['format'] != null ? options['format'] : AmfSocket.FORMAT_AMF3;
    }

    //
    // Instance variables.
    //
    private var _host:String = null;
    private var _port:int = 0;
    private var _options:Object;
    private var _socket:AmfSocket = null; // Valid states: initialized, disconnected, connected, failed, connecting, disposed.
    private var _state:String = 'initialized';
    private var _reconnectTimer:Timer = null;
    private var _requests:Dictionary = new Dictionary();
    private var _compress:Boolean = false;
    private var _format:int = AmfSocket.FORMAT_AMF3;
    private var _reconnectHandler:Function = null;

    private var _latency:Number = 0.0;

    //
    // Getters and setters.
    //

    public function get latency():Number {
        return _latency;
    }

    //
    // Public methods.
    //

    public function connect():void {
        if (isDisconnected() || isInitialized())
            __connect();
        else
            throw new Error('Can not connect when in state: ' + _state);
    }

    public function disconnect():void {
        if (isConnected()) {
            __disconnect();
            _state = 'initialized';
        }
    }

    public function isInitialized():Boolean {
        return isState('initialized');
    }

    public function isConnected():Boolean {
        return isState('connected');
    }

    public function isDisconnected():Boolean {
        return isState('disconnected');
    }

    public function isConnecting():Boolean {
        return isState('connecting');
    }

    public function isDisposed():Boolean {
        return isState('disposed');
    }

    public function isFailed():Boolean {
        return isState('failed');
    }

    public function dispose():void {
        disconnect();

        if (_reconnectTimer) {
            _reconnectTimer.removeEventListener(TimerEvent.TIMER, reconnectTimer_timer);
            _reconnectTimer.stop();
            _reconnectTimer = null;
        }
    }

    public function deliver(rpcObject:RpcObject):void {
        try {
            var object:Object = rpcObject.toObject();
            _socket.sendObject(object);

            if (rpcObject.hasOwnProperty('__signalSucceeded__'))
                _requests[rpcObject.messageId] = rpcObject;

            rpcObject.__signalDelivered__();
        } catch (error:Error) {
            dispatchEvent(new RpcManagerEvent(RpcManagerEvent.FAILED, error));
        }
    }

    public function respond(request:RpcReceivedRequest, result:Object):void {
        if (!request.isInitialized())
            throw new Error('You must only reply to a request one time.');

        var object:Object = {}

        object.type = 'rpcResponse';
        object.response = {};
        object.response.messageId = request.messageId;
        object.response.result = result;

        _socket.sendObject(object);
    }

    //
    // Protected methods.
    //

    protected function received_message_handler(message:RpcReceivedMessage):void {
        dispatchEvent(new RpcManagerEvent(RpcManagerEvent.RECEIVED_MESSAGE, message));
    }

    protected function received_request_handler(request:RpcReceivedRequest):void {
        switch (request.command) {
            case 'amf_socket_ping':
                respond(request, 'pong');
                dispatchEvent(new RpcManagerEvent(RpcManagerEvent.RECEIVED_PING, request.params));
                break;
            default:
                dispatchEvent(new RpcManagerEvent(RpcManagerEvent.RECEIVED_REQUEST, request));
        }
    }

    //
    // Private methods.
    //

    private function isState(state:String):Boolean {
        if (_state == state)
            return true;
        else
            return false;
    }

    private function addSocketEventListeners():void {
        _socket.addEventListener(AmfSocketEvent.CONNECTED, socket_connected);
        _socket.addEventListener(AmfSocketEvent.DISCONNECTED, socket_disconnected);
        _socket.addEventListener(AmfSocketEvent.RECEIVED_OBJECT, socket_receivedObject);
        _socket.addEventListener(AmfSocketEvent.IO_ERROR, socket_ioError);
        _socket.addEventListener(AmfSocketEvent.SECURITY_ERROR, socket_securityError);
    }

    private function removeSocketEventListeners():void {
        _socket.removeEventListener(AmfSocketEvent.CONNECTED, socket_connected);
        _socket.removeEventListener(AmfSocketEvent.DISCONNECTED, socket_disconnected);
        _socket.removeEventListener(AmfSocketEvent.RECEIVED_OBJECT, socket_receivedObject);
        _socket.removeEventListener(AmfSocketEvent.IO_ERROR, socket_ioError);
        _socket.removeEventListener(AmfSocketEvent.SECURITY_ERROR, socket_securityError);
    }

    private function __connect():void {
        var OldState:String = _state;
        _state = 'connecting';

        _socket = new AmfSocket(_host, _port, _compress, _format);
        if (OldState == 'disconnected') {
            _socket.addEventListener(AmfSocketEvent.CONNECTED, socket_reconnected);
        }
        addSocketEventListeners();
        _socket.connect();
    }

    private function __disconnect():void {
        _state = 'disconnected';
        cleanUp('disconnect');
    }

    private function cleanUp(reason:String = null):void {
        if (_socket) {
            removeSocketEventListeners();
            _socket.disconnect();
            _socket = null;
        }

        for (var messageId:String in _requests) {
            var request:RpcRequest = _requests[messageId];
            request.__signalFailed__(reason);
            delete _requests[messageId];
        }
    }

    private function reconnect():void {
        __disconnect();
        __connect();
    }

    private function isValidRpcResponse(data:Object):Boolean {
        if (!(data is Object))
            return false;

        if (data.type != 'rpcResponse')
            return false;

        if (!data.hasOwnProperty('response'))
            return false;

        if (!(data.response is Object))
            return false;

        if (!data.response.hasOwnProperty('messageId'))
            return false;

        if (!(data.response.messageId is String))
            return false;

        if (!data.response.hasOwnProperty('result'))
            return false;

        if (!_requests.hasOwnProperty(data.response.messageId))
            return false;

        return true;
    }

    private function isValidRpcRequest(data:Object):Boolean {
        if (!(data is Object))
            return false;

        if (data.type != 'rpcRequest')
            return false;

        if (!data.hasOwnProperty('request'))
            return false;

        if (!(data.request is Object))
            return false;

        if (!data.request.hasOwnProperty('messageId'))
            return false;

        if (!(data.request.messageId is String))
            return false;

        if (!data.request.hasOwnProperty('command'))
            return false;

        if (!(data.request.command is String) && !(data.request.command is int))
            return false;

        if (!data.request.hasOwnProperty('params'))
            return false;

        if (!(data.request.params is Object))
            return false;


        return true;
    }

    private function isValidRpcMessage(data:Object):Boolean {
        if (!(data is Object))
            return false;

        if (data.type != 'rpcMessage')
            return false;

        if (!data.hasOwnProperty('message'))
            return false;

        if (!(data.message is Object))
            return false;

        if (!data.message.hasOwnProperty('messageId'))
            return false;

        if (!(data.message.messageId is String))
            return false;

        if (!data.message.hasOwnProperty('command'))
            return false;

        if (!(data.message.command is String) && !(data.request.command is int))
            return false;

        if (!data.message.hasOwnProperty('params'))
            return false;

        if (!(data.message.params is Object))
            return false;

        return true;
    }

    private function socket_reconnected(event:AmfSocketEvent):void {
        _socket.removeEventListener(AmfSocketEvent.CONNECTED, socket_reconnected);
        if (_reconnectHandler) {
            _reconnectHandler();
        }
    }

    //
    // Event handlers.
    //

    private function socket_connected(event:AmfSocketEvent):void {
        _state = 'connected';
    }

    private function socket_disconnected(event:AmfSocketEvent):void {
        _state = 'disconnected';
        dispatchEvent(new RpcManagerEvent(RpcManagerEvent.DISCONNECTED));
        cleanUp();
    }

    private function socket_receivedObject(event:AmfSocketEvent):void {
        var data:Object = event.data;

        if (isValidRpcResponse(data)) {
            var request:RpcRequest = _requests[data.response.messageId];
            delete _requests[data.response.messageId];
            request.__signalSucceeded__(data.response.result);
        }
        else if (isValidRpcRequest(data)) {
            var received_request:RpcReceivedRequest = new RpcReceivedRequest(data);
            received_request_handler(received_request);
        }
        else if (isValidRpcMessage(data)) {
            var received_message:RpcReceivedMessage = new RpcReceivedMessage(data);
            received_message_handler(received_message);
        }
    }

    private function socket_ioError(event:AmfSocketEvent):void {
        _state = 'failed';
        if (isFailed() || isDisconnected()) {
            dispatchEvent(new RpcManagerEvent(RpcManagerEvent.FAILED));
        } else {
            dispatchEvent(new RpcManagerEvent(RpcManagerEvent.FAILED));
        }
        cleanUp('ioError');
    }

    private function socket_securityError(event:AmfSocketEvent):void {
        _state = 'failed';
        dispatchEvent(new RpcManagerEvent(RpcManagerEvent.FAILED));
        cleanUp('securityError');
    }

    private function reconnectTimer_timer(event:TimerEvent):void {
        logger.debug("reconnect timer...");
        if (isFailed() || isDisconnected()) {
            logger.debug("reconnecting...");
            reconnect();
        }

    }
}
}
