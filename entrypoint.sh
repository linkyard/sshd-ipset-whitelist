#!/bin/bash

if [ "$1" = "apply-ipset-whitelist.sh" ]; then
  exec /apply-ipset-whitelist.sh
fi

exec "$@"
