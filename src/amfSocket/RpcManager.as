package amfSocket {
import amfSocket.events.AmfSocketEvent;
import amfSocket.events.RpcManagerEvent;

import flash.desktop.NativeApplication;
import flash.events.Event;
import flash.events.EventDispatcher;
import flash.utils.Dictionary;
import flash.utils.clearTimeout;
import flash.utils.setTimeout;

import org.as3commons.logging.api.ILogger;
import org.as3commons.logging.api.getLogger;

public class RpcManager extends EventDispatcher {
    public static const SEND_TIMEOUT:Number = 10000;
    public static const OPT_COMPRESS:String = 'compress';
    public static const OPT_FORMAT:String = 'format';
    public static const OPT_MAX_RECONNECT:String = 'maxReconnect';
    // Valid states: initialized, disconnected, connected, failed, connecting, disposed.
    public static const ST_INITIALIZED:String = 'initialized';
    public static const ST_CONNECTED:String = 'connected';
    public static const ST_DISCONNECTED:String = 'disconnected';
    public static const ST_CONNECTING:String = 'connecting';
    public static const ST_DISPOSED:String = 'disposed';
    public static const ST_FAILED:String = 'failed';
    // interval
    private static const logger:ILogger = getLogger(RpcManager);
    private static const AMF_SOCKET_PING:String = 'amf_socket_ping';
    private static const CMD_PONG:String = 'pong';
    private static const MAX_RECONNECT:int = 5;

    public function RpcManager(host:String, port:int, reconnector:Reconnector = null, options:Object = null) {
        super();

        _host = host;
        _port = port;
        _reconnecter = reconnector instanceof Reconnector ? reconnector : new Reconnector();
        _reconnecter.addEventListener(Reconnector.BEFORE_CONNECT_DONE, reconnect);
        _reconnecter.addEventListener(Reconnector.AFTER_CONNECT_DONE, sendBufferedRpc);

        if (options == null)
            options = {};

        _maxReconnect = options[OPT_MAX_RECONNECT] != null ? options[OPT_MAX_RECONNECT] : MAX_RECONNECT;
        _compress = options[OPT_COMPRESS] != null && options[OPT_COMPRESS] != false;
        _format = options[OPT_FORMAT] != null ? options[OPT_FORMAT] : AmfSocket.FORMAT_AMF3;

        NativeApplication.nativeApplication.addEventListener(Event.DEACTIVATE, onAppDeactivate);
    }

    private var _host:String = null;
    private var _port:int = 0;
    private var _socket:AmfSocket = null;

    //
    // Getters and setters.
    //
    private var _reconnecter:Reconnector = null;
    private var _reconnectTimes:int = -1;
    private var _maxReconnect:int = 0;
    private var _state:String = ST_INITIALIZED;
    private var _requests:Dictionary = new Dictionary();
    private var _requestTimers:Dictionary = new Dictionary();
    private var _compress:Boolean = false;
    private var _requestQueue:Array = [];
    private var _responseQueue:Array = [];
    private var _format:int = AmfSocket.FORMAT_AMF3;

    public function connect():void {
        if (isDisconnected() || isInitialized())
            __connect();
        else
            throw new Error('Can not connect when in state: ' + _state);
    }

    public function disconnect():void {
        if (isConnected()) {
            __disconnect();
            _state = ST_INITIALIZED;
        }
    }

    public function isInitialized():Boolean {
        return isState(ST_INITIALIZED);
    }

    public function isConnected():Boolean {
        return isState(ST_CONNECTED);
    }

    public function isDisconnected():Boolean {
        return isState(ST_DISCONNECTED);
    }

    public function isConnecting():Boolean {
        return isState(ST_CONNECTING);
    }

    public function isDisposed():Boolean {
        return isState(ST_DISPOSED);
    }

    public function isFailed():Boolean {
        return isState(ST_FAILED);
    }

    public function dispose():void {
        disconnect();
    }

    public function deliver(rpcObject:RpcObject):void {
        if (!_socket || !_socket.connected) {
            if (_reconnectTimes < _maxReconnect) {
                _requestQueue.push(rpcObject);
                prepareReconnect();
            } else {
                fail();
                rpcObject.__signalFailed__('timeout');
            }
            return;
        }
        sendRequest(rpcObject);
    }

    public function respond(request:RpcReceivedRequest, result:Object):void {
        if (!request.isInitialized())
            throw new Error('You must only reply to a request one time.');

        var object:Object = {}
        object.type = 'rpcResponse';
        object.response = {};
        object.response.messageId = request.messageId;
        object.response.result = result;
        object.state = 'initialized';

        if (!_socket || !_socket.connected) {
            if (_reconnectTimes < _maxReconnect) {
                _responseQueue.push(result);
                _reconnecter.beforeConnect();
            } else {
                fail();
            }
            return;
        }
        sendResponse(object);
    }

    public function cleanRpcObject():void {
        for each (var rpcObject:RpcObject in _requestQueue) {
            rpcObject.__signalDropped__();
        }
        _requestQueue = [];
        cleanRequests();
    }

    public function failRequests():void {
        for each (var rpcObject:RpcObject in _requestQueue) {
            rpcObject.__signalFailed__();
        }
        _requestQueue = [];
        for (var messageId:String in _requests) {
            var request:RpcRequest = _requests[messageId];
            request.__signalFailed__();
            delete _requests[messageId];
        }
    }

    public function clearRequestTimers():void {
        for (var messageId:String in _requestTimers) {
            var timerId:uint = _requestTimers[messageId];
            clearTimeout(timerId);
            delete _requestTimers[messageId];
        }
    }

    protected function received_message_handler(message:RpcReceivedMessage):void {
        dispatchEvent(new RpcManagerEvent(RpcManagerEvent.RECEIVED_MESSAGE, message));
    }

    protected function received_request_handler(request:RpcReceivedRequest):void {
        switch (request.command) {
            case AMF_SOCKET_PING:
                respond(request, CMD_PONG);
                dispatchEvent(new RpcManagerEvent(RpcManagerEvent.RECEIVED_PING, request.params));
                break;
            default:
                dispatchEvent(new RpcManagerEvent(RpcManagerEvent.RECEIVED_REQUEST, request));
        }
    }

    private function cleanRequests():void {
        for (var messageId:String in _requests) {
            var request:RpcRequest = _requests[messageId];
            request.__signalDropped__();
            delete _requests[messageId];
        }
    }

    private function prepareReconnect():void {
        if (_state == ST_CONNECTING) {
            logger.debug("in connecting, can't reconnect");
            return;
        }
        _reconnecter.beforeConnect();
    }

    private function fail():void {
        _responseQueue = [];
        failRequests();
        clearRequestTimers();
        _state = ST_FAILED;
        _reconnectTimes = -1;
        dispatchEvent(new RpcManagerEvent(RpcManagerEvent.FAILED, 'reconnect failed'));
    }

    private function sendResponse(object:Object):void {
        var timerId:uint = setTimeout(function ():void {
            if (object.state != 'delivered') {
                logger.error("object timeout {0}", [JSON.stringify(object, null, 4)]);
            }
            delete _requestTimers[object.response.messageId];
        }, SEND_TIMEOUT);

        _requestTimers[object.response.messageId] = timerId;
        _socket.sendObject(object);
        object.state = 'delivered';
    }

    private function sendRequest(rpcObject:RpcObject):void {
        try {
            var needResponse:Boolean = rpcObject.hasOwnProperty('__signalSucceeded__');
            setRpcTimeout(needResponse, rpcObject);
            var object:Object = rpcObject.toObject();
            _socket.sendObject(object);

            if (needResponse) {
                _requests[rpcObject.messageId] = rpcObject;
            }

            rpcObject.__signalDelivered__();
        } catch (error:Error) {
            logger.debug("caught error when delivering {0}, {1}", [JSON.stringify(error, null, 4), error.getStackTrace()]);
            dispatchEvent(new RpcManagerEvent(RpcManagerEvent.FAILED, error));
        }
    }

    private function setRpcTimeout(needResponse:Boolean, rpcObject:RpcObject):void {
        var timerId:uint;
        if (needResponse) {
            timerId = setTimeout(function ():void {
                if (rpcObject && (rpcObject.isInitialized() || rpcObject.isDelivered())) {
                    rpcObject.__signalFailed__('timeout');
                }
                delete _requestTimers[rpcObject.messageId];
            }, SEND_TIMEOUT);
        } else {
            timerId = setTimeout(function ():void {
                if (rpcObject && rpcObject.isInitialized()) {
                    rpcObject.__signalDropped__('timeout');
                }
                delete _requestTimers[rpcObject.messageId];
            }, SEND_TIMEOUT);
        }
        _requestTimers[rpcObject.messageId] = timerId;
    }

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
        try {
            _state = ST_CONNECTING;
            _socket = new AmfSocket(_host, _port, _compress, _format);
            addSocketEventListeners();
            _socket.connect();
        } catch (error:Error) {
            logger.debug("caught error when connecting {0}, {1}", [JSON.stringify(error, null, 4), error.getStackTrace()]);
            dispatchEvent(new RpcManagerEvent(RpcManagerEvent.FAILED, error));
        }

    }

    private function __disconnect():void {
        _state = ST_DISCONNECTED;
        cleanUp('disconnect');
    }

    private function cleanUp(reason:String = "clean"):void {
        cleanSocket();
        cleanRpcObject();
        clearRequestTimers();
    }

    private function cleanSocket():void {
        if (_socket) {
            _socket.disconnect();
            removeSocketEventListeners();
            _socket = null;
        }
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

        if (!(data.message.command is String) && !(data.message.command is int))
            return false;

        if (!data.message.hasOwnProperty('params'))
            return false;

        if (!(data.message.params is Object))
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

    private function incReconnectTimes():void {
        _reconnectTimes = _reconnectTimes != -1 ? _reconnectTimes + 1 : _reconnectTimes;
    }

    public function reconnect(event:Event):void {
        _state = ST_DISCONNECTED;
        cleanSocket();
        clearRequestTimers();
        cleanRequests();
        logger.debug("reconnect times: {0}", [_reconnectTimes]);
        _reconnectTimes = _reconnectTimes < 0 ? 0 : _reconnectTimes;
        __connect();
    }

    private function onAppDeactivate(event:Event):void {
        _responseQueue = [];
        cleanRpcObject();
        clearRequestTimers();
    }

    private function sendBufferedRpc(event:Event):void {
        for (var i:int = 0; i < _requestQueue.length; i++) {
            var rpcObject:RpcObject = _requestQueue[i];
            sendRequest(rpcObject);
        }
        _requestQueue = [];
        for (var j:int = 0; j < _responseQueue.length; j++) {
            var response:Object = _responseQueue[j];
            sendResponse(response);
        }
        _responseQueue = [];
    }

    private function socket_connected(event:AmfSocketEvent):void {
        _state = ST_CONNECTED;
        _reconnectTimes = 0;
        _reconnecter.afterConnect();
        dispatchEvent(new RpcManagerEvent(RpcManagerEvent.CONNECTED));
    }

    private function socket_disconnected(event:AmfSocketEvent):void {
        _state = ST_DISCONNECTED;
        incReconnectTimes();
        dispatchEvent(new RpcManagerEvent(RpcManagerEvent.DISCONNECTED));
        cleanUp();
    }

    private function socket_receivedObject(event:AmfSocketEvent):void {
        var data:Object = event.data;

        if (isValidRpcResponse(data)) {
            var request:RpcRequest = _requests[data.response.messageId];
            delete _requests[data.response.messageId];
            clearTimeout(_requestTimers[data.response.messageId]);
            delete _requestTimers[data.response.messageId];
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
        _state = ST_FAILED;
        incReconnectTimes();
        if (isFailed() || isDisconnected()) {
            logger.debug("caught error when io error ");
            dispatchEvent(new RpcManagerEvent(RpcManagerEvent.FAILED));
        }
        cleanUp('ioError');
    }

    private function socket_securityError(event:AmfSocketEvent):void {
        _state = ST_FAILED;
        incReconnectTimes();
        logger.debug("caught error when io security error ");
        dispatchEvent(new RpcManagerEvent(RpcManagerEvent.FAILED));
        cleanUp('securityError');
    }
}
}
