#!/bin/bash

main() {
    echo "Running checks for proper environment:"
    echo "Checking that riak_mesos_scheduler directory exists"
    [ -d "riak_mesos_scheduler" ] || exit
    echo "Checking for riak_mesos_scheduler executable"
    [ -x "riak_mesos_scheduler/bin/riak_mesos_scheduler" ] || exit
    echo "Checking for required mesos env vars"
    echo "Checking if HOME is set..."
    if [ -z "$HOME" ]; then
        export HOME=`eval echo "~$WHOAMI"`
    fi

    echo "Starting riak_mesos_scheduler..."
    riak_mesos_scheduler/bin/riak_mesos_scheduler console -noinput
}

main "$@"
