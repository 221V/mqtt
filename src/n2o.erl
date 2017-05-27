-module(n2o).
-description('N2O Protocol Server for MQTT').
-author('Maxim Sokhatsky').
-license('ISC').
-behaviour(supervisor).
-behaviour(application).
-include("n2o.hrl").
-include("emqttd.hrl").
-compile(export_all).
-export([start/2, stop/1, init/1, proc/2]).

%%                                               N2O Topic Format
%%
%% Client: 1. actions/emqttd_198234215548221
%% Server: 2. events/index/maxim@synrc.com/emqttd_198234215548221
%%         3. events/login/anon/emqttd_198234215548221
%% Review: 4. room/n2o

load(Env) ->
    emqttd:hook('client.connected',    fun ?MODULE:on_client_connected/3,     [Env]),
    emqttd:hook('client.disconnected', fun ?MODULE:on_client_disconnected/3,  [Env]),
    emqttd:hook('client.subscribe',    fun ?MODULE:on_client_subscribe/4,     [Env]),
    emqttd:hook('client.unsubscribe',  fun ?MODULE:on_client_unsubscribe/4,   [Env]),
    emqttd:hook('session.created',     fun ?MODULE:on_session_created/3,      [Env]),
    emqttd:hook('session.subscribed',  fun ?MODULE:on_session_subscribed/4,   [Env]),
    emqttd:hook('session.unsubscribed',fun ?MODULE:on_session_unsubscribed/4, [Env]),
    emqttd:hook('session.terminated',  fun ?MODULE:on_session_terminated/4,   [Env]),
    emqttd:hook('message.publish',     fun ?MODULE:on_message_publish/2,      [Env]),
    emqttd:hook('message.delivered',   fun ?MODULE:on_message_delivered/4,    [Env]),
    emqttd:hook('message.acked',       fun ?MODULE:on_message_acked/4,        [Env]).

tables()   -> [ cookies, caching ].
opt()      -> [ set, named_table, { keypos, 1 }, public ].
stop(_)    -> unload(), ok.
start(_,_) -> load([]), X = supervisor:start_link({local,n2o},n2o, []),
              n2o_async:start(#handler{module=?MODULE,class=system,group=n2o,state=[],name="timer"}),
              X.
init([])   -> [ ets:new(T,opt()) || T <- tables() ],
              { ok, { { one_for_one, 5, 10 }, [] } }.

% Dead Simple Plugin Filter
% No Server Processes Involved
% No Echo
% Limited QoS = 0 for sending actions

on_client_connected(ConnAck, Client = #mqtt_client{client_id  = ClientId,
                                                   client_pid = ClientPid,
                                                   username   = Username}, Env) ->
    io:format("~n~nclient ~p connected, connack: ~p~n", [ClientId, {Username, ConnAck, Env}]),
    Replace = fun(Topic) -> rep(<<"%u">>, Username, rep(<<"%c">>, ClientId, Topic)) end,
    Topics = [{<<"actions/%c">>, 2}],
    TopicTable = [{Replace(Topic), Qos} || {Topic, Qos} <- Topics],
    ClientPid ! {subscribe, TopicTable},
    ClientPid = self(),
    {ok, Client}.

on_client_disconnected(Reason, _Client = #mqtt_client{client_id = ClientId}, _Env) ->
    io:format("client ~s disconnected, reason: ~w\r~n", [ClientId, Reason]),
    ok.

rep(<<"%c">>, ClientId, Topic)  -> emqttd_topic:feed_var(<<"%c">>, ClientId,   Topic);
rep(<<"%u">>, undefined, Topic) -> emqttd_topic:feed_var(<<"%u">>, <<"anon">>, Topic);
rep(<<"%u">>, Username, Topic)  -> emqttd_topic:feed_var(<<"%u">>, Username,   Topic).

send(X,Y) -> gproc:send({p,l,X},Y).
reg(Pool) -> reg(Pool,undefined).
reg(X,Y) ->
    case cache({pool,X}) of
         undefined -> gproc:reg({p,l,X},Y), cache({pool,X},X);
                 _ -> skip end.

on_client_subscribe(_ClientId, _Username, TopicTable, _Env) ->
    io:format("client subscribed ~p.~n", [TopicTable]),
    {ok, TopicTable}.

on_client_unsubscribe(ClientId, _Username, TopicTable, _Env) ->
    io:format("client ~p unsubscribe ~p.~n", [ClientId, TopicTable]),
    {ok, TopicTable}.

on_session_created(ClientId, _Username, _Env) ->
    io:format("session ~p created.", [ClientId]).

on_session_subscribed(ClientId, _Username, {Topic, Opts}, _Env) ->
    io:format("session ~p subscribed: ~p.~n", [ClientId, Topic]),
    {ok, {Topic, Opts}}.

on_session_unsubscribed(ClientId, _Username, {Topic, Opts}, _Env) ->
    io:format("session ~p unsubscribed: ~p.~n", [ClientId, {Topic, Opts}]),
    ok.

on_session_terminated(ClientId, _Username, _Reason, _Env) ->
    io:format("session ~p terminated.", [ClientId]).

on_message_publish(Message = #mqtt_message{topic = <<"actions/",
                   _/binary>> = Topic,
                   from=From}, _Env) ->
    io:format("on_message_publish: ~p~n", [{actions, Topic, From}]),
    {ok, Message};

% TODO: Move to DHT Supervisor with subscription to events/#

on_message_publish(Message = #mqtt_message{topic = <<"events/",
                   RestTopic/binary>>,
                   from={ClientId,_Undefined},
                   payload = Payload}, _Env) ->
    Address = emqttd_topic:words(RestTopic),
    BERT    = binary_to_term(Payload,[safe]),
    io:format("BERT: ~tp~nAddress: ~p~n",[BERT,Address]),
    io:format("on_message_publish: ~p~n", [{events, RestTopic, ClientId}]),
    case Address of
         [Mod, _Username, _JavaScriptId] ->
         Topic  = iolist_to_binary(["actions/",ClientId]),
         Module = erlang:binary_to_atom(Mod, utf8),
         Cx     = #cx{module=Module,session=ClientId,formatter=bert},
         put(context,Cx),
         case n2o_proto:info(BERT,[],Cx) of
            {reply, {binary, Msg}, _, _} -> send_reply(ClientId, Topic, Msg);
            Return -> io:format("ERR: Invalid Return ~p~n",  [Return]), ok end;
           Address -> io:format("ERR: Unknown Address ~p~n",[Address]), ok end,
    {ok, Message};

on_message_publish(Message, _) ->
    {ok,Message}.

% TODO: Eliminate qos=0 limitation

send_reply(ClientId, Topic, Message) ->
    spawn(fun() -> emqttd:publish(emqttd_message:make(ClientId, Topic, Message)) end).

on_message_delivered(ClientId, _Username, Message, _Env) ->
    io:format("message ~p delivered.\r~n", [ClientId]),
    {ok,Message}.

on_message_acked(ClientId, _Username, Message = #mqtt_message{topic = <<"events/",_/binary>>}, _Env) ->
    io:format("client ~p acked.\r~n", [ClientId]),
    {ok,Message};

on_message_acked(ClientId, _Username, Message, _Env) ->
    io:format("client ~p acked~n",[ClientId]),
    {ok,Message}.

unload() ->
    emqttd:unhook('client.connected',     fun ?MODULE:on_client_connected/3),
    emqttd:unhook('client.disconnected',  fun ?MODULE:on_client_disconnected/3),
    emqttd:unhook('client.subscribe',     fun ?MODULE:on_client_subscribe/4),
    emqttd:unhook('client.unsubscribe',   fun ?MODULE:on_client_unsubscribe/4),
    emqttd:unhook('session.subscribed',   fun ?MODULE:on_session_subscribed/4),
    emqttd:unhook('session.unsubscribed', fun ?MODULE:on_session_unsubscribed/4),
    emqttd:unhook('message.publish',      fun ?MODULE:on_message_publish/2),
    emqttd:unhook('message.delivered',    fun ?MODULE:on_message_delivered/4),
    emqttd:unhook('message.acked',        fun ?MODULE:on_message_acked/4).

% Pickling n2o:pickle/1

-ifndef(PICKLER).
-define(PICKLER, (application:get_env(n2o,pickler,n2o_secret))).
-endif.

pickle(Data) -> ?PICKLER:pickle(Data).
depickle(SerializedData) -> ?PICKLER:depickle(SerializedData).

% Error handler n2o:error/2 n2o:stack/2

-ifndef(ERRORING).
-define(ERRORING, (application:get_env(n2o,erroring,n2o))).
-endif.

stack(Error, Reason) -> ?ERRORING:stack_trace(Error, Reason).
error(Class, Error) -> ?ERRORING:error_page(Class, Error).

% Formatter

format(Term) -> format(Term,application:get_env(n2o,formatter,bert)).
format(Message, Formatter) -> n2o_format:format(Message, Formatter).

% Cache facilities n2o:cache/[1,2,3]

proc(init,#handler{}=Async) ->
    io:format("Proc Init: ~p\r~n",[init]),
    Timer = timer_restart(ping()),
    {ok,Async#handler{state=Timer}};

proc({timer,ping},#handler{state=Timer}=Async) ->
    case Timer of undefined -> skip; _ -> erlang:cancel_timer(Timer) end,
    io:format("n2o Timer: ~p\r~n",[ping]),
    n2o:invalidate_cache(),
    {reply,ok,Async#handler{state=timer_restart(ping())}}.

timer_restart(Diff) -> {X,Y,Z} = Diff, erlang:send_after(1000*(Z+60*Y+60*60*X),self(),{timer,ping}).
ping() -> application:get_env(n2o,timer,{0,10,0}).

invalidate_cache() -> ets:foldl(fun(X,_) -> n2o:cache(element(1,X)) end, 0, caching).

ttl() -> application:get_env(n2o,ttl,60*1).
till(Now,TTL) ->
    calendar:gregorian_seconds_to_datetime(
        calendar:datetime_to_gregorian_seconds(Now) + TTL), infinity.

cache(Key, undefined) -> ets:delete(caching,Key);
cache(Key, Value) -> ets:insert(caching,{Key,till(calendar:local_time(), ttl()),Value}), Value.
cache(Key, Value, Till) -> ets:insert(caching,{Key,Till,Value}), Value.
cache(Key) ->
    Res = ets:lookup(caching,Key),
    Val = case Res of [] -> []; [Value] -> Value; Values -> Values end,
    case Val of [] -> [];
                {_,infinity,X} -> X;
                {_,Expire,X} -> case Expire < calendar:local_time() of
                                  true ->  ets:delete(caching,Key), [];
                                  false -> X end end.

% Context Variables and URL Query Strings from ?REQ and ?CTX n2o:q/1 n2o:qc/[1,2]

q(Key) -> Val = get(Key), case Val of undefined -> qc(Key); A -> A end.
qc(Key) -> CX = get(context), qc(Key,CX).
qc(Key,Ctx) -> proplists:get_value(iolist_to_binary(Key),Ctx#cx.params).

atom(List) when is_list(List) -> list_to_atom(string:join([ lists:concat([L]) || L <- List],"_"));
atom(Scalar) -> list_to_atom(lists:concat([Scalar])).

% These api are not really API

temp_id() -> "auto" ++ integer_to_list(erlang:unique_integer() rem 1000000).
append(List, Key, Value) -> case Value of undefined -> List; _A -> [{Key, Value}|List] end.
render(X) -> wf_render:render(X).

version() -> proplists:get_value(vsn,element(2,application:get_all_key(n2o))).

keyset(Name,Pos,List,New) ->
    case lists:keyfind(Name,Pos,List) of
        false -> [New|List];
        _Element -> lists:keyreplace(Name,Pos,List,New) end.

actions() -> get(actions).
actions(Ac) -> put(actions,Ac).

clear_actions() -> put(actions,[]).
add_action(Action) ->
    Actions = case get(actions) of undefined -> []; E -> E end,
    put(actions,Actions++[Action]).

fold(Fun,Handlers,Ctx) ->
    lists:foldl(fun({_,Module},Ctx1) ->
        {ok,_,NewCtx} = Module:Fun([],Ctx1),
        NewCtx end,Ctx,Handlers).

stack_trace(Error, Reason) ->
    Stacktrace = [case A of
         { Module,Function,Arity,Location} ->
             { Module,Function,Arity,proplists:get_value(line, Location) };
         Else -> Else end
    || A <- erlang:get_stacktrace()],
    [Error, Reason, Stacktrace].

error_page(Class,Error) ->
    io_lib:format("ERROR:  ~w:~w\r~n\r~n",[Class,Error]) ++
    "STACK: " ++
    [ io_lib:format("\t~w:~w/~w:~w\n",
        [ Module,Function,Arity,proplists:get_value(line, Location) ])
    ||  { Module,Function,Arity,Location} <- erlang:get_stacktrace() ].

user() -> case session(<<"user">>) of undefined -> []; E -> nitro:to_list(E) end.
user(User) -> session(<<"user">>,User).

-ifndef(SESSION).
-define(SESSION, n2o).
-endif.

session(Key) -> ?SESSION:get_value(Key,undefined).
session(Key, Value) -> ?SESSION:set_value(Key, Value).

set_value(Key, Value) -> erlang:put(Key,Value).
get_value(Key, DefaultValue) -> case erlang:get(Key) of
                                     undefined -> DefaultValue;
                                     Value -> Value end.
