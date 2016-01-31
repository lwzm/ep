-module(tcp).

-export([run/0, tcp_accept/2, udp_read/2, q/0]).
-export([tcp_accept_start/2]).
-export([monitor/0]).
-define(ID_SIZE, 12).
-define(PACKET_HEAD_MAX_SIZE, 2).
-define(ACTIVE_TIMES, 10).


run() ->
    Port = args_port(),
    DownstreamPort = Port + 1,
    {ok, DownstreamAddress} = inet:getaddr("localhost", inet),
    {ok, TCPSocket} = gen_tcp:listen(Port, [{backlog, 1024},  % lots of clients are connecting
                                            {packet, args_packet_type()},  % 1, 2, or line
                                            {packet_size, 65507 - ?PACKET_HEAD_MAX_SIZE - ?ID_SIZE},  % same as max length of UDP message
                                            binary, {active, false}]),
    {ok, UDPSocket} = gen_udp:open(Port, [binary, {active, true}]),
    Downstream = {UDPSocket, DownstreamAddress, DownstreamPort},
    TCPAcceptPid = spawn(?MODULE, tcp_accept, [TCPSocket, Downstream]),
    UDPReaderPid = spawn(?MODULE, udp_read, [Downstream, dict:new()]),
    true = register(my_tcp, TCPAcceptPid),
    true = register(my_udp, UDPReaderPid),
    ok = gen_tcp:controlling_process(TCPSocket, TCPAcceptPid),
    ok = gen_udp:controlling_process(UDPSocket, UDPReaderPid),

    true = register(my_monitor, spawn(?MODULE, monitor, [])),

    running.


args_port() -> args_port(init:get_argument(port)).
args_port({ok, [[N]]}) -> list_to_integer(N);
args_port(_) -> 1111.

args_packet_type() -> args_packet_type(init:get_argument('packet-type')).
args_packet_type({ok, [["1"]]}) -> 1;
args_packet_type({ok, [["2"]]}) -> 2;
args_packet_type(_) -> line.


monitor() ->
    process_flag(trap_exit, true),
    receive
        {monitor, Pid} ->
            link(Pid);
        {'EXIT', _Pid, _Why} ->
            %io:format("EXIT ~p ~p ~n", [_Pid, _Why]),
            known;
        _ ->
            clean
    end,
    monitor().


tcp_accept(LSocket, Downstream) ->
    tcp_accept(LSocket, Downstream, 0).

tcp_accept(LSocket, Downstream, N) ->
    receive
        count ->
            io:format("tcp_accept count: ~p ~n", [N]);
        Msg ->
            io:format("tcp_accept receive ~p ~n", [Msg])
    after 0 ->
              clean
    end,
    case gen_tcp:accept(LSocket, 1000) of
        {ok, ASocket} ->
            inet:setopts(ASocket, [{active, once}]),
            Pid = spawn(?MODULE, tcp_accept_start, [ASocket, Downstream]),
            gen_tcp:controlling_process(ASocket, Pid),
            my_monitor ! {monitor, Pid},
            tcp_accept(LSocket, Downstream, N + 1);
        {error,timeout} ->
            tcp_accept(LSocket, Downstream, N);
        Other ->
            io:format("tcp_accept Other ~p ~n", [Other]),
            tcp_accept(LSocket, Downstream, N)
    end.


tcp_accept_start(Socket, Downstream) ->
    receive
        {tcp, Socket, Data} ->
            <<ID:?ID_SIZE/binary, _/binary>> = <<Data/binary, <<0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0>>/binary>>,
            %io:format("~p ~p ~n", [ID, Data]),
            my_udp ! {client_login, ID, self()},%login
            inet:setopts(Socket, [{active, ?ACTIVE_TIMES}]),
            tcp_accept_loop(Socket, ID, Downstream);
        {tcp_closed, Socket} ->
            io:format("tcp_accept_start interrupted ~p ~n", [Socket]);
        Other ->
            io:format("tcp_accept_start error ~p ~n", [Other])
    end.


tcp_accept_loop(Socket, ID, {UDPSocket, Address, Port}=Downstream) ->
    receive
        {tcp, Socket, Data} ->
            %io:format("socket ~p recv: ~p ~n", [Socket, Data]),
            gen_udp:send(UDPSocket, Address, Port, <<ID/binary, Data/binary>>),
            tcp_accept_loop(Socket, ID, Downstream);
        {reply_to_client, Data} ->
            gen_tcp:send(Socket, Data),
            tcp_accept_loop(Socket, ID, Downstream);
        {tcp_passive, Socket} ->
            ok = inet:setopts(Socket, [{active, ?ACTIVE_TIMES}]),
            tcp_accept_loop(Socket, ID, Downstream);
        {kick, ID} ->
            % do not: my_udp ! {client_logout, ID},
            over;
        _Other ->
            %io:format("~p ~p received unknown: ~p ~n", [self(), Socket, Other]),
            my_udp ! {client_logout, ID},
            over
    end.


udp_read({Socket, DownstreamAddress, DownstreamPort}=Downstream, Onlines) ->
    OnlinesNew =
    receive
        {udp, Socket, DownstreamAddress, DownstreamPort, Bin} ->
            try
                <<ID:?ID_SIZE/binary, Data/binary>> = Bin,
                reply_to_client(dict:find(ID, Onlines), Data)
            catch
                error:X ->
                    io:format("udp_read error: ~p ~n", [X]),
                    {error, X}
            end,
            Onlines;
        {udp, Socket, Address, Port, Bin} ->
            Data = list_to_binary(format("~p~n~p~n", [dict:size(Onlines), get_process_info(Bin)])),
            gen_udp:send(Socket, Address, Port, Data),
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
    udp_read(Downstream, OnlinesNew).

get_process_info(undefined) ->
    error;
get_process_info(Name) when is_binary(Name) ->
    get_process_info(binary_to_list(Name));
get_process_info(Name) when is_list(Name) ->
    get_process_info(list_to_atom(string:strip(Name, both, $\n)));
get_process_info(Name) when is_atom(Name) ->
    get_process_info(whereis(Name));
get_process_info(Pid) when is_pid(Pid) ->
    erlang:process_info(Pid, message_queue_len).

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

format(Format, Data) ->
    lists:flatten(io_lib:format(Format, Data)).

