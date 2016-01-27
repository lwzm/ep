#!/usr/bin/env python3

import datetime
import socket
import sys
import os
import random
import time


def test():
    t = datetime.datetime.now()
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(0.01)
    s.connect(('localhost', 1111))
    lost = 0
    for i in range(int(sys.argv[1])):
        s.sendall(bytes(random.randint(20, 255) for _ in range(32)) + b'\n')
        try:
            time.sleep(0.001)
            s.recv(1024)
        except socket.timeout:
            lost += 1
    print(datetime.datetime.now() - t, i + 1, lost)
    time.sleep(10)


def main():
    N = 30
    for i in range(N):
        pid = os.fork()
        if pid == 0:
            test()
            break
    else:
        for i in range(N):
            print(os.wait())


def main2():
    t = datetime.datetime.now()
    N = 30000
    ss = []
    for i in range(N):
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.connect(('localhost', 1111))
        ss.append(s)
        #print(s)
    print(datetime.datetime.now() - t)

    time.sleep(10)

    t = datetime.datetime.now()
    for s in ss:
        s.close()
    print(datetime.datetime.now() - t)


if __name__ == "__main__":
    sys.argv.append(10000)
    main2()
