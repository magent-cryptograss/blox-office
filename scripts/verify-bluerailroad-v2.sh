#!/bin/bash
# Verify BlueRailroadTrainV2 on Optimism Etherscan
#
# Usage:
#   export OPTIMISM_ETHERSCAN_API_KEY="your-api-key"
#   ./scripts/verify-bluerailroad-v2.sh
#
# Get an API key from: https://optimistic.etherscan.io/myapikey

set -e

if [ -z "$OPTIMISM_ETHERSCAN_API_KEY" ]; then
    echo "Error: OPTIMISM_ETHERSCAN_API_KEY not set"
    echo "Get one from: https://optimistic.etherscan.io/myapikey"
    exit 1
fi

cd "$(dirname "$0")/.."

CONSTRUCTOR_ARGS=$(~/.foundry/bin/cast abi-encode "constructor(address,address)" \
    0x067ace39fbbfd3c3f7cef9ed77590383345994fe \
    0xCe09A2d0d0BDE635722D8EF31901b430E651dB52)

# EVM version to try (cancun, paris, london, shanghai)
EVM_VERSION="${1:-cancun}"

echo "Trying EVM version: $EVM_VERSION"
echo "If this fails, try: ./scripts/verify-bluerailroad-v2.sh paris"
echo ""

~/.foundry/bin/forge verify-contract \
    --chain-id 10 \
    --compiler-version "v0.8.33+commit.64118f21" \
    --constructor-args "$CONSTRUCTOR_ARGS" \
    --evm-version "$EVM_VERSION" \
    0x7C3aEBcD477C591EbCde3bC247B3A9531814B4B7 \
    contracts/BlueRailroadTrainV2.sol:BlueRailroadTrainV2 \
    --etherscan-api-key "$OPTIMISM_ETHERSCAN_API_KEY" \
    --watch
