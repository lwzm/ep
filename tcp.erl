-module(tcp).

-export([run/0, tcp_accept/2, udp_read/2, q/0]).
-export([tcp_accept_loop/3]).
-export([monitor/0]).
-define(DOWNSTREAM_PORT, 1514).
-define(ACTIVE_TIMES, 10).

run() ->
    Port = 1111,
    DownstreamHost = "localhost",
    {ok, DownstreamAddress} = inet:getaddr(DownstreamHost, inet),
    {ok, TCPSocket} = gen_tcp:listen(Port, [binary, {active, false}, {backlog, 1024}]),
    {ok, UDPSocket} = gen_udp:open(Port, [binary, {active, true}]),
    TCPAcceptPid = spawn(?MODULE, tcp_accept, [TCPSocket, {UDPSocket, DownstreamAddress, ?DOWNSTREAM_PORT}]),
    UDPReaderPid = spawn(?MODULE, udp_read, [UDPSocket, dict:new()]),
    true = register(my_tcp, TCPAcceptPid),
    true = register(my_udp, UDPReaderPid),
    ok = gen_tcp:controlling_process(TCPSocket, TCPAcceptPid),
    ok = gen_udp:controlling_process(UDPSocket, UDPReaderPid),

    true = register(monitor, spawn(?MODULE, monitor, [])),

    running.

monitor() ->
    process_flag(trap_exit, true),
    receive
        {monitor, Pid} ->
            link(Pid);
        {'EXIT', Pid, Why} ->
            io:format("EXIT ~p ~p ~n", [Pid, Why]),
            print
    end,
    monitor().


tcp_accept(LSocket, Downstream) ->
    tcp_accept(LSocket, 0, Downstream).

tcp_accept(LSocket, ID, Downstream) ->
    {ok, ASocket} = gen_tcp:accept(LSocket),
    %io:format("tcp accept: ~p -> ~p ~n", [LSocket, ASocket]),
    Pid = spawn(?MODULE, tcp_accept_loop, [ASocket, ID, Downstream]),
    monitor ! {monitor, Pid},
    my_udp ! {client_login, ID, Pid},%login
    gen_tcp:controlling_process(ASocket, Pid),
    inet:setopts(ASocket, [{packet, line}, {active, ?ACTIVE_TIMES}]),
    tcp_accept(LSocket, (ID + 1) band 16#FFFF, Downstream).


tcp_accept_loop(Socket, ID, {UDPSocket, Address, Port}=Downstream) ->
    Over =
    receive
        {tcp, Socket, Data} ->
            %io:format("socket ~p recv: ~p ~n", [Socket, Data]),
            ok = gen_udp:send(UDPSocket, Address, Port, <<ID:16, Data/binary>>),
            case Data of
                <<"q!\n">> ->
                    over;
                _ ->
                    continue
            end;
        {reply_to_client, Data} ->
            ok = gen_tcp:send(Socket, Data);
        {tcp_passive, Socket} ->
            ok = inet:setopts(Socket, [{active, ?ACTIVE_TIMES}]);
        {tcp_closed, Socket} ->
            %io:format("socket ~p closed ~n", [Socket]),
            my_udp ! {client_logout, ID},
            over;
        Other ->
            io:format("~p ~p received unknown: ~p ~n", [self(), Socket, Other]),
            over
    end,

    case Over of
        over ->
            over;
        _ ->
            tcp_accept_loop(Socket, ID, Downstream)
    end.


udp_read(Socket, Onlines) ->
    OnlinesNew =
    receive
        {udp, Socket, _Host, ?DOWNSTREAM_PORT, Bin} ->
            %io:format("server received:~p from ~p:~p~n", [Bin, Host, Port]), 
            try
                <<ID:16, Data/binary>> = Bin,
                reply_to_client(dict:find(ID, Onlines), Data)
            catch
                error:X ->
                    io:format("udp_read error: ~p ~n", [X]),
                    {error, X}
            end,
            Onlines;
        {client_login, ID, Pid} ->
            dict:store(ID, Pid, Onlines);
        {client_logout, ID} ->
            dict:erase(ID, Onlines);
        {q, Pid} ->
            Pid ! {dict:size(Onlines), erlang:length(get()), erlang:process_info(self(), message_queue_len)},
            Onlines;
        Other ->
            io:format("my_udp received unknown: ~p ~n", [Other]),
            Onlines
    end,
    udp_read(Socket, OnlinesNew).

q() ->
    my_udp ! {q, self()},
    receive
        Msg ->
            io:format("~p ~n", [Msg])
    end.

reply_to_client({ok, Pid}, Data) ->
    Pid ! {reply_to_client, Data};
reply_to_client(error, _Data) ->
    do_nothing.
