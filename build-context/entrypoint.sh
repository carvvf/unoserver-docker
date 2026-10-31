#!/bin/bash
set -e -u

# Function to wait for unoserver to start
wait_for_unoserver() {
    echo "Waiting for unoserver to start on port 2003..."
    while ! netstat -tln | grep -q 2003; do
        sleep 1
    done
    echo "unoserver started."
}

# Run unoserver as a service that cannot stay up while unable to convert.
#
# unoserver serves one request at a time, so without a timeout one document that hangs
# LibreOffice blocks every later conversion. Its --conversion-timeout alone is not enough:
# it kills soffice.bin but then waits on oosplash, which outlives it, so the process stays up
# and the port stays open while every later conversion fails, and a health check on the port
# keeps passing.
#
# So this script, which is PID 1, exits as soon as it sees that timeout. The kernel then ends
# every process in the container, including one that is hung or ignores signals, and the
# restart policy brings up a clean service.
run_unoserver() {
    local conversion_timeout="${UNOSERVER_CONVERSION_TIMEOUT:-60}"
    case "${conversion_timeout}" in
        '' | 0 | *[!0-9]*)
            echo "UNOSERVER_CONVERSION_TIMEOUT must be a positive number of seconds, got: ${conversion_timeout}" >&2
            exit 2
            ;;
    esac
    echo "Conversion timeout: ${conversion_timeout} seconds."

    trap 'exit 0' TERM INT

    local line
    while IFS= read -r line; do
        printf '%s\n' "${line}"
        case "${line}" in
            *"Conversion timeout"*)
                echo "A conversion exceeded ${conversion_timeout} seconds; exiting so that the service restarts." >&2
                exit 1
                ;;
        esac
    done < <(unoserver --interface 0.0.0.0 --conversion-timeout "${conversion_timeout}" 2>&1)
    echo "unoserver stopped; exiting." >&2
    exit 1
}

export PS1='\u@\h:\w\$ '

echo "using: $(libreoffice --version)"

# if tty then assume that container is interactive
if [ ! -t 0 ]; then
    echo "Running unoserver-docker in non-interactive."
    echo "For interactive mode use '-it', e.g. 'docker run -v /tmp:/data -it unoserver/unoserver-docker'."

    run_unoserver
    # # run supervisord in foreground
    # supervisord -c "$SUPERVISOR_NON_INTERACTIVE_CONF"
else
    echo "Running unoserver-docker in interactive mode."
    echo "For non-interactive mode omit '-it', e.g. 'docker run -p 2003:2003 unoserver/unoserver-docker'."

    # default parameters for supervisord
    export SUPERVISOR_INTERACTIVE_CONF='/supervisor/conf/interactive/supervisord.conf'
    export UNIX_HTTP_SERVER_PASSWORD=${UNIX_HTTP_SERVER_PASSWORD:-$(cat /proc/sys/kernel/random/uuid)}

    # run supervisord as detached
    supervisord -c "$SUPERVISOR_INTERACTIVE_CONF"

    # wait until unoserver started and listens on port 2002.
    wait_for_unoserver
    
    # if commands have been passed to container run them and exit, else start bash
    if [[ $# -gt 0 ]]; then
        eval "$@"
    else
        /bin/bash
    fi
fi
