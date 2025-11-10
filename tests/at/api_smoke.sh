#!/usr/bin/env bash

# Main entry point for API smoke tests
# Runs all modular test suites and provides comprehensive summary

set -euo pipefail

# Change to script directory
cd "$(dirname "$0")"

# Source common utilities
source ./test_common.sh

# Ensure BASE is set (fallback to localhost) before any usage
: "${BASE:=http://localhost:8080}"

# Color codes for output
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Test suite tracking (bash 3.2 compatible)
TEST_SUITES="test_health.sh test_auth.sh test_order_create.sh test_order_get.sh test_order_cancel.sh test_reserve.sh test_pickup.sh test_deliver.sh test_fail.sh test_workflows.sh test_heartbeat.sh test_assignment.sh test_broken_drone.sh test_fix_drone.sh test_admin_order_patch.sh test_admin_drone_list.sh"

# Parallel arrays for results (bash 3.2 compatible)
SUITE_NAMES=()
SUITE_RESULTS=()
SUITE_PASSED=()
SUITE_FAILED=()
TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_TESTS=0

# Header
echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD}  Drone Delivery API - Smoke Test Suite${NC}"
echo -e "${BOLD}========================================${NC}"
echo ""
echo -e "${BLUE}Running comprehensive API test coverage...${NC}"
echo "BASE=${BASE}"
echo ""

# Check if server is running
check_server() {
    if ! curl -s "${BASE}/health" > /dev/null 2>&1; then
        echo -e "${RED}ERROR: API server is not running at ${BASE}${NC}"
        echo "Please start the server first:"
        echo "  cd /Users/asddsa/go/github/enas/drone-delivery-management"
        echo "  make run"
        exit 1
    fi
}

# Run a single test suite
run_suite() {
    local suite="$1"
    local suite_name="${suite%.sh}"
    
    echo -e "${BOLD}${BLUE}Running ${suite_name}...${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    if [[ ! -f "$suite" ]]; then
        echo -e "${RED}SKIP: Test suite not found${NC}"
        SUITE_NAMES+=("$suite_name")
        SUITE_RESULTS+=("SKIP")
        SUITE_PASSED+=(0)
        SUITE_FAILED+=(0)
        echo ""
        return
    fi
    
    # Run the test suite and capture output
    set +e
    local output
    output=$(bash "$suite" 2>&1)
    local exit_code=$?
    set -e
    
    # Extract test results from output (strip ANSI color codes first)
    local passed=0
    local failed=0
    local output_clean
    output_clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    
    if echo "$output_clean" | grep -q "Passed:"; then
        passed=$(echo "$output_clean" | grep "Passed:" | grep -oE '[0-9]+' | head -1)
        failed=$(echo "$output_clean" | grep "Failed:" | grep -oE '[0-9]+' | head -1)
    fi
    
    # Print the output
    echo "$output"
    
    # Decide result
    local result="SKIP"
    if [[ $failed -eq 0 && $passed -gt 0 ]]; then
        result="PASS"
        echo -e "${GREEN}✓ ${suite_name}: ALL TESTS PASSED${NC}"
    else
        if [[ $passed -eq 0 && $failed -eq 0 ]]; then
            # No summary detected. If suite exited non-zero, treat as FAIL, not SKIP
            if [[ $exit_code -ne 0 ]]; then
                result="FAIL"
                echo -e "${RED}✗ ${suite_name}: SUITE EXITED EARLY (exit ${exit_code})${NC}"
            else
                echo -e "${YELLOW}⊘ ${suite_name}: NO TESTS RUN${NC}"
            fi
        else
            result="FAIL"
            echo -e "${RED}✗ ${suite_name}: SOME TESTS FAILED${NC}"
        fi
    fi
    
    SUITE_NAMES+=("$suite_name")
    SUITE_RESULTS+=("$result")
    SUITE_PASSED+=($passed)
    SUITE_FAILED+=($failed)
    
    TOTAL_PASSED=$((TOTAL_PASSED + passed))
    TOTAL_FAILED=$((TOTAL_FAILED + failed))
    TOTAL_TESTS=$((TOTAL_TESTS + passed + failed))
    
    echo ""
}

# Print final summary
print_final_summary() {
    echo ""
    echo -e "${BOLD}========================================${NC}"
    echo -e "${BOLD}  TEST SUITE SUMMARY${NC}"
    echo -e "${BOLD}========================================${NC}"
    echo ""
    
    # Iterate over results arrays
    local idx=0
    for suite_name in "${SUITE_NAMES[@]}"; do
        local result="${SUITE_RESULTS[$idx]}"
        local passed="${SUITE_PASSED[$idx]}"
        local failed="${SUITE_FAILED[$idx]}"
        local total=$((passed + failed))
        
        printf "%-25s " "$suite_name:"
        
        if [[ "$result" == "PASS" ]]; then
            echo -e "${GREEN}✓ PASS${NC} (${passed}/${total})"
        elif [[ "$result" == "FAIL" ]]; then
            if [[ $total -gt 0 ]]; then
              echo -e "${RED}✗ FAIL${NC} (${passed}/${total}, ${failed} failed)"
            else
              echo -e "${RED}✗ FAIL${NC} (suite error)"
            fi
        else
            echo -e "${YELLOW}⊘ SKIP${NC}"
        fi
        
        idx=$((idx + 1))
    done
    
    echo ""
    echo -e "${BOLD}========================================${NC}"
    echo -e "${BOLD}OVERALL RESULTS${NC}"
    echo -e "${BOLD}========================================${NC}"
    echo ""
    echo -e "Total Tests:       ${BOLD}${TOTAL_TESTS}${NC}"
    echo -e "Tests Passed:      ${GREEN}${BOLD}${TOTAL_PASSED}${NC}"
    echo -e "Tests Failed:      ${RED}${BOLD}${TOTAL_FAILED}${NC}"
    
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        local pass_rate=$(awk "BEGIN {printf \"%.1f\", ($TOTAL_PASSED/$TOTAL_TESTS)*100}")
        echo -e "Pass Rate:         ${BOLD}${pass_rate}%${NC}"
    fi
    
    echo ""
    
    if [[ $TOTAL_FAILED -eq 0 && $TOTAL_TESTS -gt 0 ]]; then
        echo -e "${GREEN}${BOLD}🎉 ALL TESTS PASSED! 🎉${NC}"
        echo ""
        exit 0
    elif [[ $TOTAL_FAILED -gt 0 ]]; then
        echo -e "${RED}${BOLD}❌ SOME TESTS FAILED${NC}"
        echo ""
        echo "Review the output above for details on failed tests."
        echo ""
        exit 1
    else
        echo -e "${YELLOW}${BOLD}⚠️  NO TESTS RUN${NC}"
        echo ""
        exit 1
    fi
}

# Main execution
main() {
    # Check server availability
    check_server
    
    # Run all test suites
    for suite in $TEST_SUITES; do
        run_suite "$suite"
    done
    
    # Print final summary
    print_final_summary
}

# Run main function
main
