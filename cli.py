#!/usr/bin/env python3

import datetime
import socket
import sys
import os
import random
import time


def test(N):
    t = datetime.datetime.now()
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(0.01)
    s.connect(('localhost', 1111))
    lost = 0
    for i in range(N):
        s.sendall(bytes(random.randint(20, 255) for _ in range(32)) + b'\n')
        try:
            time.sleep(0.001)
            s.recv(1024)
        except socket.timeout:
            lost += 1
    print(datetime.datetime.now() - t, i + 1, lost)
    s.close()


def main():
    N = int(sys.argv[1])
    C = 5
    for i in range(C):
        pid = os.fork()
        if pid == 0:
            test(N)
            break
    else:
        for i in range(C):
            print(os.wait())


def main2():
    t = datetime.datetime.now()
    N = 10000
    ss = []
    for i in range(N):
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.connect(('localhost', 1111))
        ss.append(s)
        #print(s)
    print(datetime.datetime.now() - t)

    input("continue...")

    t = datetime.datetime.now()
    for s in ss:
        s.close()
    print(datetime.datetime.now() - t)


if __name__ == "__main__":
    sys.argv.append(10000)
    main()
