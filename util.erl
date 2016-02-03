-module(util).

-compile(export_all).


print(Data) ->
    io:format("~p~n", [Data]).


%% rpc:call('tcp@sv.q', util, reload, [util]).
reload(Module) ->
    code:purge(Module),
    {module, Module} = code:load_file(Module).
