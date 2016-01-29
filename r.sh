#!/bin/sh
erlc -o ebin tcp.erl
supervisorctl restart erl
