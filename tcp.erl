-module(tcp).

-export([run/0, tcp_accept/2, udp_read/2, q/0]).
-export([tcp_accept_loop/3]).
-define(PORT, 1024).
-define(ACTIVE_TIMES, 10).

run() ->
    Port = 1111,
    {DownstreamHost, DownstreamPort} = {"localhost", 1514},
    {ok, DownstreamAddress} = inet:getaddr(DownstreamHost, inet),
    {ok, TCPSocket} = gen_tcp:listen(Port, [binary, {active, false}, {backlog, 1024}]),
    {ok, UDPSocket} = gen_udp:open(Port, [binary, {active, true}]),
    TCPAcceptPid = spawn(?MODULE, tcp_accept, [TCPSocket, {UDPSocket, DownstreamAddress, DownstreamPort}]),
    UDPReaderPid = spawn(?MODULE, udp_read, [UDPSocket, dict:new()]),
    register(my_tcp, TCPAcceptPid),
    register(my_udp, UDPReaderPid),
    gen_tcp:controlling_process(TCPSocket, TCPAcceptPid),
    gen_udp:controlling_process(UDPSocket, UDPReaderPid),
    running.


tcp_accept(LSocket, Downstream) ->
    tcp_accept(LSocket, 0, Downstream).

tcp_accept(LSocket, ID, Downstream) ->
    {ok, ASocket} = gen_tcp:accept(LSocket),
    %io:format("tcp accept: ~p -> ~p ~n", [LSocket, ASocket]),
    Pid = spawn(?MODULE, tcp_accept_loop, [ASocket, ID, Downstream]),
    my_udp ! {client_login, ID, Pid},%login
    gen_tcp:controlling_process(ASocket, Pid),
    inet:setopts(ASocket, [{packet, line}, {active, ?ACTIVE_TIMES}]),
    tcp_accept(LSocket, (ID + 1) band 16#FFFF, Downstream).

logout(<<"q\n">>, Socket) ->
    gen_tcp:close(Socket),
    self() ! {tcp_closed, Socket};
logout(_, _) -> x.

tcp_accept_loop(Socket, ID, {UDPSocket, Address, Port}=Downstream) ->
    Over =
    receive
        {tcp, Socket, Data} ->
            %io:format("socket ~p recv: ~p ~n", [Socket, Data]),
            %logout(Data, Socket),
            gen_udp:send(UDPSocket, Address, Port, <<ID:16, Data/binary>>);
        {reply_to_client, Data} ->
            gen_tcp:send(Socket, Data);
        {tcp_passive, Socket} ->
            inet:setopts(Socket, [{active, ?ACTIVE_TIMES}]);
        {tcp_closed, Socket} ->
            %io:format("socket ~p closed ~n", [Socket]),
            my_udp ! {client_logout, ID},
            over;
        Err ->
            io:format("socket error: ~p ~n", [Err])
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
        {udp, Socket, _Host, _Port, Bin} ->
            %io:format("server received:~p from ~p:~p~n", [Bin, Host, Port]), 
            try
                <<ID:16, Data/binary>> = Bin,
                reply_to_client(dict:find(ID, Onlines), Data)
            catch
                error:X ->
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
            io:format("server received: ~p ~n", [Other]),
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
