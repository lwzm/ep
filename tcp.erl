-module(tcp).

-export([run/0, tcp_accept/1, udp_read/1, udp_write/1]).
-export([tcp_accept_loop/2]).
-define(PORT, 1024).

run() ->
    Port = 1111,
    {ok, TCPSocket} = gen_tcp:listen(Port, [binary, {active, false}]),
    {ok, UDPSocket} = gen_udp:open(Port, [binary, {active, true}]),
    TCPAcceptPid = spawn(?MODULE, tcp_accept, [TCPSocket]),
    UDPReaderPid = spawn(?MODULE, udp_read, [UDPSocket]),
    UDPWriterPid = spawn(?MODULE, udp_write, [UDPSocket]),
    register(my_tcp, TCPAcceptPid),
    register(my_udp_reader, UDPReaderPid),
    register(my_udp_writer, UDPWriterPid),
    gen_tcp:controlling_process(TCPSocket, TCPAcceptPid),
    gen_udp:controlling_process(UDPSocket, UDPReaderPid),
    running.


tcp_accept(LSocket) ->
    tcp_accept(LSocket, 0).

tcp_accept(LSocket, ID) ->
    {ok, ASocket} = gen_tcp:accept(LSocket),
    io:format("tcp accept: ~p -> ~p ~n", [LSocket, ASocket]),
    Pid = spawn(?MODULE, tcp_accept_loop, [ASocket, ID]),
    my_udp_reader ! {client_login, ID, Pid},%login
    gen_tcp:controlling_process(ASocket, Pid),
    inet:setopts(ASocket, [{packet, line}, {active, 3}]),
    tcp_accept(LSocket, ID + 1).


tcp_accept_loop(Socket, ID) ->
    receive
        {tcp, Socket, Data} ->
            my_udp_writer ! {to_py, ID, Data},
            %io:format("socket ~p recv: ~p ~n", [Socket, Data]),
            tcp_recv;
        {reply_client, Data} ->
            gen_tcp:send(Socket, Data),
            %io:format("socket ~p recv: ~p ~n", [Socket, Data]),
            tcp_reply;
        {tcp_passive, Socket} ->
            inet:setopts(Socket, [{active, 3}]),
            %io:format("socket ~p is passive, please call continue/1 ~p ~n", [Socket, self()]);
            passive;
        {tcp_closed, Socket} ->
            %io:format("socket ~p closed ~n", [Socket]),
            my_udp_reader ! {client_logout, ID},
            tcp_close;
        Err ->
            io:format("socket error: ~p ~n", [Err])
    end,
    tcp_accept_loop(Socket, ID).


udp_read(Socket) ->
    receive
        {udp, Socket, Host, Port, Bin} ->
            %io:format("server received:~p from ~p:~p~n", [Bin, Host, Port]), 
            <<ID, Data/binary>> = Bin,
            send_to_tcp_client(get(ID), Data),
            udp;
        {client_login, ID, Pid} ->
            put(ID, Pid),
            client_login_and_record_client;
        {client_logout, ID} ->
            erase(ID),
            io:format("logout and ~p ~n", [get()]), 
            client_logout_and_erase_client;
        Other ->
            io:format("server received: ~p ~n", [Other])
    end,
    udp_read(Socket).


send_to_tcp_client(undefined, _Data) ->
    do_nothing;
send_to_tcp_client(Pid, Data) when is_pid(Pid) ->
    Pid ! {reply_client, Data}.

udp_write(Socket) ->
    receive
        {to_py, ID, Data} ->
            %io:format("~p ~p ~p ~n", [ID, Data, <<ID, Data/binary>>]),
            gen_udp:send(Socket, "sv", 1514, <<ID, Data/binary>>),
            to_py;
        Other ->
            io:format("server received: ~p ~n", [Other])
    end,
    udp_write(Socket).
