-module(tcp).

-export([run/0, tcp_accept/2, udp_read/2, q/0]).
-export([tcp_accept_start/2]).
-export([monitor/0]).
-define(ID_SIZE, 12).
-define(PACKET_HEAD_MAX_SIZE, 2).
-define(DOWNSTREAM_PORT, 1514).
-define(ACTIVE_TIMES, 10).


run() ->
    Port = 1111,
    DownstreamHost = "localhost",
    {ok, DownstreamAddress} = inet:getaddr(DownstreamHost, inet),
    {ok, TCPSocket} = gen_tcp:listen(Port, [{backlog, 1024},  % lots of clients are connecting
                                            {packet, get_packet_type()},  % 1, 2, or line
                                            {packet_size, 65507 - ?PACKET_HEAD_MAX_SIZE - ?ID_SIZE},  % same as max length of UDP message
                                            binary, {active, true}]),
    {ok, UDPSocket} = gen_udp:open(Port, [binary, {active, true}]),
    TCPAcceptPid = spawn(?MODULE, tcp_accept, [TCPSocket, {UDPSocket, DownstreamAddress, ?DOWNSTREAM_PORT}]),
    UDPReaderPid = spawn(?MODULE, udp_read, [UDPSocket, dict:new()]),
    true = register(my_tcp, TCPAcceptPid),
    true = register(my_udp, UDPReaderPid),
    ok = gen_tcp:controlling_process(TCPSocket, TCPAcceptPid),
    ok = gen_udp:controlling_process(UDPSocket, UDPReaderPid),

    true = register(monitor, spawn(?MODULE, monitor, [])),

    running.


get_packet_type() -> get_packet_type(init:get_argument('packet-type')).
get_packet_type({ok, [["1"]]}) -> 1;
get_packet_type({ok, [["2"]]}) -> 2;
get_packet_type(_) -> line.


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
    {ok, ASocket} = gen_tcp:accept(LSocket),
    Pid = spawn(?MODULE, tcp_accept_start, [ASocket, Downstream]),
    gen_tcp:controlling_process(ASocket, Pid),
    monitor ! {monitor, Pid},
    tcp_accept(LSocket, Downstream).


tcp_accept_start(Socket, Downstream) ->
    receive
        {tcp, Socket, Data} ->
            <<ID:?ID_SIZE/binary, _/binary>> = <<Data/binary, <<0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0>>/binary>>,
            io:format("~p ~p ~n", [ID, Data]),
            my_udp ! {client_login, ID, self()},%login
            inet:setopts(Socket, [{active, ?ACTIVE_TIMES}]),
            tcp_accept_loop(Socket, ID, Downstream);
        Other ->
            io:format("~p ~n", [Other])
    end.


tcp_accept_loop(Socket, ID, {UDPSocket, Address, Port}=Downstream) ->
    Over =
    receive
        {tcp, Socket, Data} ->
            %io:format("socket ~p recv: ~p ~n", [Socket, Data]),
            ok = gen_udp:send(UDPSocket, Address, Port, <<ID/binary, Data/binary>>),
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
        {kick, ID} ->
            over;
        Other ->
            io:format("~p ~p received unknown: ~p ~n", [self(), Socket, Other]),
            my_udp ! {client_logout, ID},
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
                <<ID:?ID_SIZE/binary, Data/binary>> = Bin,
                reply_to_client(dict:find(ID, Onlines), Data)
            catch
                error:X ->
                    io:format("udp_read error: ~p ~n", [X]),
                    {error, X}
            end,
            Onlines;
        {client_login, ID, Pid} ->
            kick_another_client(dict:find(ID, Onlines), ID),
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

kick_another_client({ok, Pid}, ID) ->
    Pid ! {kick, ID};
kick_another_client(error, _) ->
    do_nothing.

reply_to_client({ok, Pid}, Data) ->
    Pid ! {reply_to_client, Data};
reply_to_client(error, _) ->
    do_nothing.
