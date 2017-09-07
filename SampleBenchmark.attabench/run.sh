#!/bin/sh

set -e
exec xcrun swift run -c release -Xswiftc -whole-module-optimization Benchmark "$@"
