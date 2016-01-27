#!/usr/bin/env python3

import datetime
import logging
import multiprocessing
import os
import signal
import sys


num_of_children = 0 if len(sys.argv) < 2 else int(sys.argv[1])
assert num_of_children >= 0, num_of_children
children = []


def log_to_stderr(*args):
    print(datetime.datetime.now(), *args, file=sys.stderr)


def _term(signal_number=None, stack_frame=None):
    log_to_stderr("SIGTERM", len(children), children)
    dead_children = []
    for seq, pid in children:
        os.kill(pid, signal.SIGTERM)
        dead_children.append(os.wait())
    log_to_stderr("waited", len(dead_children), dead_children)
    sys.exit()


def bind_udp_socket(port, host="0.0.0.0"):
    import socket
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind((host, port))
    return s


def loop(port=1514):
    s = bind_udp_socket(port)

    num_of_locks = (num_of_children + 1) ** 2
    assert num_of_locks == pow(num_of_children + 1, 2), num_of_locks
    _Lock = multiprocessing.Lock or multiprocessing.Semaphore
    locks = [_Lock() for _ in range(num_of_locks)]

    for i in range(num_of_children):
        seq = i + 1
        pid = os.fork()
        if pid == 0:  # child
            break
        children.append((seq, pid))
    else:  # only father run these
        seq = 0
        signal.signal(signal.SIGTERM, _term)
        with open(".pid", "w") as f:
            f.write(str(os.getpid()))
        log_to_stderr("father and children:", os.getpid(), children)

    pid = os.getpid()
    msg = None

    while True:
        try:
            msg, addr = s.recvfrom(65536)

            lock_id = sum(msg[:12]) % num_of_locks

            with locks[lock_id]:
                #print(seq, pid, msg)
                #msg = str(, [addr, pid]).encode() + msg
                s.sendto(msg, addr)

        except Exception as e:
            logging.exception(
                "{} {} {}".format(datetime.datetime.now(), e, msg))


if __name__ == "__main__":
    loop()
