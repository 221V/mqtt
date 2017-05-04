-ifndef(N2O_HRL).

-define(N2O_HRL, true).

-record(handler, { name, module, class, group, config, state}).
-record(cx,      { handlers, actions, req, module, lang, path, session, formatter=false, params, form, state=[] }).

-define(CTX(ClientId), n2o:cache(ClientId)).
-define(REQ(ClientId), (n2o:cache(ClientId))#cx.req).

% API

-define(FAULTER_API, [error_page/2]).
-define(PICKLES_API, [pickle/1, depickle/1]).

-define(N2O_JSON, (application:get_env(n2o,json,jsone))).

% IO protocol

-record(io,      { eval, data }).
-record(bin,     { data }).
-record(client,  { data }).
-record(server,  { data }).

% Nitrogen Protocol

-record(pickle,  { source, pickled, args }).
-record(flush,   { data }).
-record(direct,  { data }).
-record(ev,      { module, msg, trigger, name }).

% File Transfer Protocol

-record(ftp,     { id, sid, filename, meta, size, offset, block, data, status }).
-record(ftpack,  { id, sid, filename, meta, size, offset, block, data, status }).

-endif.
