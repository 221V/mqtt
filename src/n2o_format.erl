-module(n2o_format).
-description('N2O Fortmatter: JSON, BERT').
-license('ISC').
-copyright('Maxim Sokhatsky').
-include("n2o.hrl").
-compile(export_all).

% TODO 4.5+: should be compiled from config

io(Data)     -> iolist_to_binary(Data).
bin(Data)    -> Data.
list(Data)   -> binary_to_list(term_to_binary(Data)).
format(Term) -> format(Term,?CTX#cx.formatter).

% JSON Encoder

format({Io,Eval,Data}, json) ->
    n2o:info(?MODULE,"JSON {~p,_,_}: ~tp~n",[Io,io(Eval)]),
    ?N2O_JSON:encode([{t,104},{v,[
                     [{t,100},{v,io}],
                     [{t,109},{v,io(Eval)}],
                     [{t,109},{v,list(Data)}]]}]);

format({Atom,Data}, json) ->
    n2o:info(?MODULE,"JSON {~p,_}: ~tp~n",[Atom,list(Data)]),
    ?N2O_JSON:encode([{t,104},{v,[
                     [{t,100},{v,Atom}],
                     [{t,109},{v,list(Data)}]]}]);

% BERT Encoder

format({Io,Eval,Data}, bert) ->
    n2o:info(?MODULE,"BERT {~p,_,_}: ~tp~n",[Io,{io,io(Eval),bin(Data)}]),
    term_to_binary({Io,io(Eval),bin(Data)});

format({bin,Data}, bert) ->
    n2o:info(?MODULE,"BERT {bin,_}: ~tp~n",[Data]),
    term_to_binary({bin,Data});

format({Atom,Data}, bert) ->
    n2o:info(?MODULE,"BERT {~p,_}: ~tp~n",[Atom,bin(Data)]),
    term_to_binary({Atom,bin(Data)});

format(#ftp{}=FTP, bert) ->
    n2o:info(?MODULE,"BERT {ftp,_,_,_,_,_,_,_,_,_,_,_,_}: ~tp~n",
             [FTP#ftp{data= <<>>}]),
    term_to_binary(FTP);

format(Term, bert) ->
    term_to_binary(Term);

format(_,_) ->
    term_to_binary({error,<<>>,
            <<"Only JSON/BERT formatters are available.">>}).