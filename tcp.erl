-module(tcp).

-export([run/0, tcp_accept/2, udp_read/2, udp_write/3]).
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
    UDPWriterPid = spawn(?MODULE, udp_write, [UDPSocket, DownstreamAddress, DownstreamPort]),
    register(my_tcp, TCPAcceptPid),
    register(my_udp_reader, UDPReaderPid),
    register(my_udp_writer, UDPWriterPid),
    gen_tcp:controlling_process(TCPSocket, TCPAcceptPid),
    gen_udp:controlling_process(UDPSocket, UDPReaderPid),
    running.


tcp_accept(LSocket, Downstream) ->
    tcp_accept(LSocket, 0, Downstream).

tcp_accept(LSocket, ID, Downstream) ->
    {ok, ASocket} = gen_tcp:accept(LSocket),
    %io:format("tcp accept: ~p -> ~p ~n", [LSocket, ASocket]),
    Pid = spawn(?MODULE, tcp_accept_loop, [ASocket, ID, Downstream]),
    my_udp_reader ! {client_login, ID, Pid},%login
    gen_tcp:controlling_process(ASocket, Pid),
    inet:setopts(ASocket, [{packet, line}, {active, ?ACTIVE_TIMES}]),
    tcp_accept(LSocket, (ID + 1) band 16#FFFF, Downstream).


tcp_accept_loop(Socket, ID, {UDPSocket, Address, Port}=Downstream) ->
    receive
        {tcp, Socket, Data} ->
            gen_udp:send(UDPSocket, Address, Port, <<ID:16, Data/binary>>),
            %my_udp_writer ! {to_py, ID, Data},
            %io:format("socket ~p recv: ~p ~n", [Socket, Data]),
            tcp_recv;
        {reply_client, Data} ->
            gen_tcp:send(Socket, Data),
            %io:format("socket ~p recv: ~p ~n", [Socket, Data]),
            tcp_reply;
        {tcp_passive, Socket} ->
            inet:setopts(Socket, [{active, ?ACTIVE_TIMES}]),
            %io:format("socket ~p is passive, please call continue/1 ~p ~n", [Socket, self()]);
            passive;
        {tcp_closed, Socket} ->
            %io:format("socket ~p closed ~n", [Socket]),
            my_udp_reader ! {client_logout, ID},
            tcp_close;
        Err ->
            io:format("socket error: ~p ~n", [Err])
    end,
    tcp_accept_loop(Socket, ID, Downstream).


udp_read(Socket, Onlines) ->
    OnlinesNew =
    receive
        {udp, Socket, _Host, _Port, Bin} ->
            %io:format("server received:~p from ~p:~p~n", [Bin, Host, Port]), 
            <<ID:16, Data/binary>> = Bin,
            %Pid = get(ID),
            Pid = dict:find(ID, Onlines),
            send_to_tcp_client(Pid, Data),
            Onlines;
        {client_login, ID, Pid} ->
            put(ID, Pid),
            dict:store(ID, Pid, Onlines);
        {client_logout, ID} ->
            %io:format("logout and ~p ~n", [get()]), 
            erase(ID),
            dict:erase(ID, Onlines);
        Other ->
            io:format("server received: ~p ~n", [Other]),
            io:format("~p ~p ~p ~n",
                      [dict:size(Onlines),
                       erlang:length(get()),
                       erlang:process_info(self(), message_queue_len)]),
            Onlines
    end,
    udp_read(Socket, OnlinesNew).


send_to_tcp_client(undefined, _Data) ->
    do_nothing;
send_to_tcp_client(error, _Data) ->
    do_nothing;
send_to_tcp_client({ok, Pid}, Data) ->
    send_to_tcp_client(Pid, Data);
send_to_tcp_client(Pid, Data) when is_pid(Pid) ->
    Pid ! {reply_client, Data}.

udp_write(Socket, Address, Port) ->
    receive
        {to_py, ID, Data} ->
            %io:format("~p ~p ~p ~n", [ID, Data, <<ID, Data/binary>>]),
            gen_udp:send(Socket, Address, Port, <<ID, Data/binary>>),
            to_py;
        Other ->
            io:format("server received: ~p ~n", [Other])
    end,
    udp_write(Socket, Address, Port).
