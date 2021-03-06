#!/usr/bin/env python3

import datetime
import socket
import sys
import os
import random
import struct
import time

PORT = 1111
PORT = 1024

_int_16 = struct.Struct("!H").pack

def pack_bytes_with_head(bs):
    if isinstance(bs, str):
        bs = bs.encode()
    return _int_16(len(bs)) + bs


def new_tcp_client():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(0.01)
    s.connect(('localhost', PORT))
    return s


def test(N, i):
    t = datetime.datetime.now()
    s = new_tcp_client()
    lost = 0
    s.sendall(pack_bytes_with_head(bytes([i])))
    for i in range(N):
        #s.sendall(b'\0' + bytes(random.randint(20, 255) for _ in range(32)) + b'\n')
        s.sendall(pack_bytes_with_head(b'x'*64))
        try:
            time.sleep(0.001)
            s.recv(1024)
        except socket.timeout:
            lost += 1
    time.sleep(0)
    print(datetime.datetime.now() - t, i + 1, lost)
    s.close()


def main():
    N = int(sys.argv[1])
    C = 5
    for i in range(C):
        pid = os.fork()
        if pid == 0:
            test(N, i)
            break
    else:
        for i in range(C):
            print(os.wait())


def main2():
    t = datetime.datetime.now()
    N = 30000
    ss = []
    for i in range(N):
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.connect(('localhost', PORT))
        s.sendall(pack_bytes_with_head(_int_16(i)))
        ss.append(s)
        #print(s)
    print(datetime.datetime.now() - t)

    input("continue...")

    t = datetime.datetime.now()
    for s in ss:
        s.close()
    print(datetime.datetime.now() - t)


if __name__ == "__main__":
    sys.argv.append(10)
    main()
