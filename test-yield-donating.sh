#!/bin/bash

# YieldDonating Strategy Fork Test Runner
# This script runs the YieldDonating tests on a Base mainnet fork

set -e

echo "========================================="
echo "YieldDonating Strategy - Fork Tests"
echo "========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if fork URL is provided or use default
FORK_URL="${BASE_RPC_URL:-https://mainnet.base.org}"

echo -e "${YELLOW}Fork URL:${NC} $FORK_URL"
echo ""

# Check if custom RPC is set
if [ "$FORK_URL" = "https://mainnet.base.org" ]; then
    echo -e "${YELLOW}⚠️  Using public Base RPC (may be slow)${NC}"
    echo -e "${YELLOW}   For faster tests, set BASE_RPC_URL to Alchemy/Infura${NC}"
    echo ""
fi

echo "Running YieldDonating fork tests..."
echo ""

# Run the tests
forge test \
    --match-path "src/test/yieldDonating/*.t.sol" \
    --fork-url "$FORK_URL" \
    -vv

# Check exit code
if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✅ All YieldDonating tests passed!${NC}"
else
    echo ""
    echo -e "${RED}❌ Some tests failed${NC}"
    exit 1
fi
