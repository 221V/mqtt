var match, pl = /\+/g, search = /([^&=]+)=?([^&]*)/g,
    decode = function (s) { return decodeURIComponent(s.replace(pl, " ")); },
    query = window.location.search.substring(1);
params = {}; while (match = search.exec(query)) params[decode(match[1])] = decode(match[2]);
l = location.pathname;
x = l.substring(l.lastIndexOf("/") + 1);
module = x.substring(0, x.lastIndexOf("."));
//var topic = module + "_" + params.room || "lobby"; // nynja://root/user/:name/actions
//var topic = module + "/" + params.room + "/user" || "lobby"; // nynja://root/user/:name/actions
//var topic = "user/anon/"

//var topic = module
//var action_topic = topic + "/actions"
//var event_topic = topic + "/events"
console.log("Room: " + params.room);
var mqtt = new Paho.MQTT.Client(host, 8083, '');
var clientId = '';

function get_topic(prefix) {
    return prefix + "/" + module + "/" + clientId;
}

var subscribeOptions = {
    qos: 0,  // QoS
    invocationContext: { foo: true },  // Passed to success / failure callback
    onSuccess: function () { console.log("N2O Subscribed"); },
    onFailure: function (m) { console.log("N2O Subscription failed: " + message.errorMessage); },
    timeout: 3
};
var options = {
    timeout: 3,
    onFailure: function (m) { console.log("N2O Connection failed: " + m.errorMessage); },
    onSuccess: function () {
        console.log("N2O Connected");
//        mqtt.subscribe(action_topic, subscribeOptions);
//        mqtt.subscribe("user/anon//actions", subscribeOptions);
     }
};
var ws = {
    send: function (payload) {
        var message = new Paho.MQTT.Message(payload);
//        message.destinationName = topic + clientId + "/event"
//        message.destinationName = event_topic; // nynja://root/user/:name/events
        message.destinationName = get_topic("events");
        message.qos = 2;
        mqtt.send(message);
    }
};

function MQTT_start() {
    mqtt.onConnectionLost = function (o) { console.log("connection lost: " + o.errorMessage); };
    mqtt.onMessageArrived = function (m) {
        words = m.destinationName.split("/");
        if (mqtt.clientId == '' && clientId == '' && words[2] == "user") {
            clientId = words[4];
        }

        var BERT = m.payloadBytes.buffer.slice(m.payloadBytes.byteOffset,
            m.payloadBytes.byteOffset + m.payloadBytes.length);
        try {
            erlang = dec(BERT);
            console.log(m.destinationName);
//            console.log(erlang);
            for (var i = 0; i < $bert.protos.length; i++) {
                p = $bert.protos[i]; if (p.on(erlang, p.do).status == "ok") return;
            }
        } catch (e) { console.log(e); }
    };
    mqtt.connect(options);
}

MQTT_start();
