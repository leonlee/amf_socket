/**
 * User: Leon
 * Date: 14-4-17
 * Time: 下午5:41
 */

package amfSocket {
import flash.events.Event;
import flash.events.EventDispatcher;

public class Reconnector extends EventDispatcher {
    public static var BEFORE_CONNECT_DONE:String = "before_connect_done";
    public static var AFTER_CONNECT_DONE:String = "after_connect_done";

    public function Reconnector() {
    }

    /**
     * Stuffs after reconnect, e.g. re-login , must call afterDone() at the end.
     */
    public function afterConnect():void {
        afterDone();
    }

    public function afterDone():void {
        dispatchEvent(new Event(AFTER_CONNECT_DONE));
    }

    /**
     * Stuffs before reconnect, e.g. clean old requests , must call beforeDone() at the end.
     */
    public function beforeConnect():void {
        beforeDone();
    }

    public function beforeDone():void {
        dispatchEvent(new Event(BEFORE_CONNECT_DONE));
    }
}
}
