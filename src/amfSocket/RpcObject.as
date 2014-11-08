package amfSocket {
import amfSocket.events.RpcObjectEvent;

import flash.events.EventDispatcher;

public class RpcObject extends EventDispatcher {
    //
    // Instance variables.
    //

    public function RpcObject(command:Object, params:Object) {
        super();

        _command = command;
        _params = params;
        _messageId = genMessageId();
        _options = {};
    }

    private var _options:Object = null;

    public function setOptions(options:Object):void {
        if (options)
            _options = options;
    }

    public function setOption(name:String, value:Object):void {
        _options[name] = value;
    }

    public function getOptions():Object {
        return _options;
    }

    public function getOption(name:String):Object {
        return _options[name];
    }

    public function hasOption(name:String):Object {
        return _options[name] != null;
    }

    private var _messageId:String = null;

    public function get messageId():String {
        return _messageId;
    }

    public function set messageId(value:String):void {
        _messageId = value;
    } // Valid states: initialized, delivered, succeeded, failed.

    //
    // Constructor.
    //

    private var _command:Object = null;

    public function get command():Object {
        return _command;
    }

    //
    // Getters and setters.
    //

    public function set command(value:Object):void {
        _command = value;
    }

    private var _params:Object = null;

    public function get params():Object {
        return _params;
    }

    public function set params(value:Object):void {
        _params = value;
    }

    private var _state:String = 'initialized';

    public function get state():String {
        return _state;
    }

    public function set state(value:String):void {
        _state = value;
    }

    public function toObject():Object {
        throw new Error('You must override toObject() in a subclass.');
    }

    //
    // Public methods.
    //

    public function isInitialized():Boolean {
        return isState('initialized');
    }

    public function isDelivered():Boolean {
        return isState('delivered');
    }

    public function isCompleted():Boolean {
        return isState('completed');
    }

    public function isFailed():Boolean {
        return isState('failed');
    }

    //
    // Protected methods.
    //

    public function __signalDelivered__():void {
        if (isInitialized()) {
            _state = 'delivered';
            dispatchEvent(new RpcObjectEvent(RpcObjectEvent.DELIVERED));
        }
        else
            throw new Error("Received 'delivered' signal an already delivered RPC request.");
    }

    public function __signalFailed__(reason:String = null):void {
//      if(isDelivered()) {
        _state = 'failed';
        dispatchEvent(new RpcObjectEvent(RpcObjectEvent.FAILED, reason));
//      }
//      else
//        throw new Error("Received 'failed' signal when not in 'delivered' state.");
    }

    public function __signalDropped__(reason:String = null):void {
        _state = 'dropped';
        dispatchEvent(new RpcObjectEvent(RpcObjectEvent.DROPPED, reason));
    }

    protected function isState(state:String):Boolean {
        if (_state == state)
            return true;
        else
            return false;
    }

    //
    // Signals.
    // Even though these are public, they should only be called by the RPC Manager.
    // Your user code should never call them directly.
    //

    protected function randomInt(begin:int = 100000000, end:int = 999999999):int {
        var num:int = Math.floor(begin + (Math.random() * (end - begin + 1)));

        return num;
    }

    protected function genMessageId():String {
        var date:Date = new Date();
        var messageId:String = date.getTime().toString() + ':' + randomInt().toString() + ':' + randomInt().toString();

        return messageId;
    }
}
}