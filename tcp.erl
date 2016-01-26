-module(tcp).

-export([run/0]).
-export([continue/1]).
-export([do_loop/1]).
-define(PORT, 1024).

run() ->
    spawn(fun() -> server(1111) end).

server(Port) ->
    {ok, LSock} = gen_tcp:listen(Port, [{active, false}]),
    io:format("tcp listen: ~p on ~p ~n", [LSock, Port]),
    accept(LSock).

accept(LSock) ->
    {ok, ASock} = gen_tcp:accept(LSock),
    io:format("tcp accept: ~p -> ~p ~n", [LSock, ASock]),
    Pid = spawn(?MODULE, do_loop, [ASock]),
    gen_tcp:controlling_process(ASock, Pid),
    inet:setopts(ASock, [{active, 1}]),
    accept(LSock).

do_loop(ASock) ->
    receive
        {tcp, Socket, Data} ->
            io:format("socket ~p recv: ~p ~n", [Socket, Data]);
        {tcp_closed, Socket} ->
            io:format("socket ~p closed ~n", [Socket]);
        {tcp_passive, Socket} ->
            io:format("socket ~p is passive, please call continue/1 ~p ~n", [Socket, self()]);
        {release_passive, N} ->
            inet:setopts(ASock, [{active, N}]);
        Err ->
            io:format("socket may error: ~p ~n", [Err])
    end,
    do_loop(ASock).

continue(Pid, N) ->
    Pid ! {release_passive, N},
    ok.

continue(Pid) ->
    continue(Pid, 3).
