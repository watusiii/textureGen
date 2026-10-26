#!/bin/sh
# Run from the MudTexture folder. Needs node and luau on PATH.
node tests/parity.mjs > tests/_parity_cases.luau && luau tests/run_parity.luau
