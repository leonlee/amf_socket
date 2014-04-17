package amfSocket.events {
import flash.events.Event;

public class RpcObjectEvent extends Event {
    //
    // Constants.
    //

    public static const DELIVERED:String = 'RPC_OBJECT_EVENT_DELIVERED';
    public static const SUCCEEDED:String = 'RPC_OBJECT_EVENT_SUCCEEDED';
    public static const FAILED:String = 'RPC_OBJECT_EVENT_FAILED';
    public static const DROPPED:String = 'RPC_OBJECT_EVENT_DROPPED';

    //
    // Instance variables.
    //

    public function RpcObjectEvent(type:String, data:Object = null, bubbles:Boolean = false, cancelable:Boolean = false) {
        _data = data;

        super(type, bubbles, cancelable);
    }

    //
    // Constructor.
    //

    private var _data:Object;

    //
    // Getters and setters.
    //

    public function get data():Object {
        return _data;
    }
}
}