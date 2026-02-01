#!/bin/bash
# Development server script for testing context compaction extension
# Runs Ollama and llms.py with the extension loaded

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
OLLAMA_HOST="http://localhost:11434"
LLMS_PORT=8000
EXTENSION_DIR="$HOME/.llms/extensions/context_compaction"
LOG_DIR="./logs"
PID_FILE="$LOG_DIR/dev-server.pid"

# Create log directory
mkdir -p "$LOG_DIR"

print_status() {
    echo -e "${BLUE}==>${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

check_ollama() {
    if ! command -v ollama &> /dev/null; then
        print_error "Ollama not found. Please install: https://ollama.ai"
        exit 1
    fi
    print_success "Ollama found"
}

check_llms() {
    if ! command -v llms &> /dev/null; then
        print_error "llms.py not found. Please install: pip install llms-py"
        exit 1
    fi
    print_success "llms.py found"
}

start_ollama() {
    if pgrep -x "ollama" > /dev/null; then
        print_success "Ollama already running"
        return 0
    fi

    print_status "Starting Ollama server..."
    ollama serve > "$LOG_DIR/ollama.log" 2>&1 &
    OLLAMA_PID=$!
    echo "$OLLAMA_PID" >> "$PID_FILE"

    # Wait for Ollama to be ready
    print_status "Waiting for Ollama to be ready..."
    for i in {1..30}; do
        if curl -s "$OLLAMA_HOST/api/tags" > /dev/null 2>&1; then
            print_success "Ollama server ready (PID: $OLLAMA_PID)"
            return 0
        fi
        sleep 1
    done

    print_error "Ollama failed to start"
    return 1
}

check_model() {
    local model="$1"
    print_status "Checking for model: $model"

    if ollama list | grep -q "$model"; then
        print_success "Model $model found"
        return 0
    else
        print_warning "Model $model not found"
        print_status "Pulling model $model (this may take a few minutes)..."
        ollama pull "$model"
        print_success "Model $model pulled successfully"
        return 0
    fi
}

install_extension() {
    # Use symlink instead of copying to avoid stale code
    if [ -L "$EXTENSION_DIR" ]; then
        print_success "Extension symlink already exists"
    elif [ -d "$EXTENSION_DIR" ]; then
        print_status "Removing old copied extension"
        rm -rf "$EXTENSION_DIR"
        print_status "Creating extension symlink to $(pwd)"
        ln -s "$(pwd)" "$EXTENSION_DIR"
        print_success "Extension symlinked (changes will be live)"
    else
        print_status "Creating extension symlink to $(pwd)"
        mkdir -p "$(dirname "$EXTENSION_DIR")"
        ln -s "$(pwd)" "$EXTENSION_DIR"
        print_success "Extension symlinked (changes will be live)"
    fi
}

setup_test_config() {
    local config_file="$EXTENSION_DIR/config.json"

    # Only create config if it doesn't exist
    if [ ! -f "$config_file" ]; then
        print_status "Creating default configuration..."

        cat > "$config_file" << 'EOF'
{
  "provider": "ollama",
  "model": "mistral:7b",
  "summary_prompt": "Create a comprehensive summary of this conversation. Focus on:\n\n- What was discussed or accomplished\n- Current state of the work/story/discussion\n- Key facts, decisions, and details\n- Important context needed to continue\n\nFor stories: Summarize plot events, characters, and current narrative state.\nFor technical discussions: Summarize code changes, decisions, files involved, and next steps.\n\nBe factual and comprehensive. Do NOT ask questions or make suggestions."
}
EOF

        print_success "Configuration created (model: qwen2.5:7b)"
    else
        print_success "Using existing configuration"
    fi
}

start_llms() {
    print_status "Starting llms.py server on port $LLMS_PORT..."

    # Initialize config if needed
    llms --init 2>/dev/null || true

    # Enable Ollama provider
    print_status "Enabling Ollama provider..."
    llms --enable ollama 2>&1 | grep -v "already enabled" || true

    # Start server with verbose logging
    if [ "${DEBUG:-0}" = "1" ]; then
        print_status "Starting with DEBUG logging enabled"
        DEBUG=1 VERBOSE=1 llms --serve $LLMS_PORT > "$LOG_DIR/llms.log" 2>&1 &
    else
        VERBOSE=1 llms --serve $LLMS_PORT > "$LOG_DIR/llms.log" 2>&1 &
    fi
    LLMS_PID=$!
    echo "$LLMS_PID" >> "$PID_FILE"

    # Wait for llms to be ready
    print_status "Waiting for llms.py to be ready..."
    for i in {1..30}; do
        if curl -s "http://localhost:$LLMS_PORT" > /dev/null 2>&1; then
            print_success "llms.py server ready (PID: $LLMS_PID)"
            return 0
        fi
        sleep 1
    done

    print_error "llms.py failed to start"
    return 1
}

follow_logs() {
    print_status "Following logs (Ctrl+C to stop)..."
    echo ""
    tail -f "$LOG_DIR/llms.log" 2>/dev/null &
    TAIL_PID=$!
    trap "kill $TAIL_PID 2>/dev/null" EXIT
    wait $TAIL_PID
}

stop_servers() {
    print_status "Stopping servers..."

    if [ -f "$PID_FILE" ]; then
        while read pid; do
            if kill -0 "$pid" 2>/dev/null; then
                kill "$pid" 2>/dev/null || true
                print_success "Stopped process $pid"
            fi
        done < "$PID_FILE"
        rm "$PID_FILE"
    fi

    # Also try to find and kill by name
    pkill -f "llms serve" 2>/dev/null || true
    pkill -f "ollama serve" 2>/dev/null || true

    print_success "Servers stopped"
}

show_status() {
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║         Context Compaction Test Environment Ready          ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Web UI:${NC}        http://localhost:$LLMS_PORT"
    echo -e "${BLUE}Ollama API:${NC}    $OLLAMA_HOST"
    echo -e "${BLUE}Extension:${NC}     $EXTENSION_DIR"
    echo ""
    echo -e "${YELLOW}Available Models:${NC}"
    ollama list 2>/dev/null | grep -E "llama3.2|qwen|gemma" | head -3 || echo "  Run: ollama list"
    echo ""
    echo -e "${YELLOW}Testing Instructions:${NC}"
    echo "  1. Open http://localhost:$LLMS_PORT in your browser"
    echo "  2. Select provider: ollama"
    echo "  3. Select model: llama3.2:3b"
    echo "  4. Start chatting"
    echo "  5. Type /compact to test manual compaction"
    echo "  6. Watch automatic compaction at 50% threshold"
    echo ""
    echo -e "${YELLOW}Debug Mode:${NC}"
    echo "  • Enable: DEBUG=1 ./dev-server.sh restart"
    echo ""
    echo -e "${YELLOW}Useful Commands:${NC}"
    echo "  • View logs:       ./dev-server.sh logs"
    echo "  • Check status:    ./dev-server.sh status"
    echo "  • Check providers: llms ls"
    echo "  • Debug mode:      DEBUG=1 ./dev-server.sh"
    echo ""
    echo -e "${GREEN}Press Ctrl+C to stop all servers${NC}"
    echo ""
}

cleanup() {
    echo ""
    print_status "Cleaning up..."
    stop_servers
    exit 0
}

# Main script
case "${1:-}" in
    ""|start)
        # Trap Ctrl+C to cleanup
        trap cleanup SIGINT SIGTERM

        print_status "Starting development environment..."
        echo ""

        # Check prerequisites
        check_ollama
        check_llms
        echo ""

        # Stop any existing servers
        stop_servers
        echo ""

        # Install/update extension
        install_extension
        echo ""

        # Setup test config
        setup_test_config
        echo ""

        # Start Ollama
        start_ollama
        echo ""

        # Check/pull model
        check_model "llama3.2:3b"
        echo ""

        # Start llms.py
        start_llms
        echo ""

        # Show status
        show_status

        # Keep running until Ctrl+C
        while true; do
            sleep 1
        done
        ;;

    logs)
        follow_logs
        ;;

    status)
        echo ""
        print_status "Checking server status..."
        echo ""

        # Check Ollama
        if pgrep -x "ollama" > /dev/null; then
            print_success "Ollama is running"
            echo "  Available models:"
            ollama list 2>/dev/null | grep -v "^NAME" | awk '{print "    " $1}' | head -5
        else
            print_error "Ollama is not running"
        fi
        echo ""

        # Check llms
        if pgrep -f "llms.*serve" > /dev/null; then
            print_success "llms.py is running"
        else
            print_error "llms.py is not running"
        fi
        echo ""

        # Check providers
        print_status "Checking llms.py providers..."
        if command -v llms &> /dev/null; then
            llms ls 2>/dev/null | grep -E "Provider|ollama|openai|anthropic" | head -10
        fi
        echo ""

        # Check web UI
        if curl -s "http://localhost:$LLMS_PORT" > /dev/null 2>&1; then
            print_success "Web UI is accessible at http://localhost:$LLMS_PORT"
        else
            print_error "Web UI is not accessible"
        fi
        echo ""

        # Check Ollama connectivity from llms
        print_status "Testing Ollama connectivity..."
        if curl -s "$OLLAMA_HOST/api/tags" > /dev/null 2>&1; then
            print_success "Ollama API responding at $OLLAMA_HOST"
        else
            print_error "Cannot connect to Ollama API at $OLLAMA_HOST"
        fi
        echo ""

        # Check extension status via logs
        print_status "Checking extension logs..."
        if grep -q "Context compaction extension loaded" "$LOG_DIR/llms.log" 2>/dev/null; then
            print_success "Extension loaded successfully"
            echo ""
            echo "Recent extension activity:"
            grep -i "compact" "$LOG_DIR/llms.log" 2>/dev/null | tail -5
        else
            print_warning "Extension load message not found in logs"
            echo "  Check: ./dev-server.sh logs | grep compact"
        fi

        echo ""
        ;;

    test)
        print_status "Running quick test..."
        echo ""

        # Check if servers are running
        if ! pgrep -f "llms.*serve" > /dev/null; then
            print_error "Servers not running. Start with: ./dev-server.sh start"
            exit 1
        fi

        print_status "Testing extension..."
        echo ""

        # Check config file
        if [ -f "$EXTENSION_DIR/config.json" ]; then
            print_success "Extension config exists"
            echo "Current configuration:"
            cat "$EXTENSION_DIR/config.json" | python3 -m json.tool
        else
            print_error "Extension config not found"
        fi
        echo ""

        # Check logs for extension activity
        print_status "Checking extension logs..."
        if grep -q "Context compaction extension loaded" "$LOG_DIR/llms.log" 2>/dev/null; then
            print_success "Extension is loaded"
            echo ""
            echo "Recent activity (last 5 lines):"
            grep -i "compact" "$LOG_DIR/llms.log" 2>/dev/null | tail -5
        else
            print_warning "Extension not detected in logs"
        fi
        echo ""

        print_success "Test complete! Monitor with: ./dev-server.sh follow"
        ;;

    diagnose)
        print_status "Running diagnostics..."
        echo ""

        # Check Ollama
        echo -e "${BLUE}=== Ollama Check ===${NC}"
        if pgrep -x "ollama" > /dev/null; then
            print_success "Ollama process running"
        else
            print_error "Ollama process not running"
            echo "  Fix: ollama serve &"
        fi

        if curl -s "$OLLAMA_HOST/api/tags" > /dev/null 2>&1; then
            print_success "Ollama API responding at $OLLAMA_HOST"
            echo "  Models available:"
            ollama list 2>/dev/null | grep -v "^NAME" | awk '{print "    " $1}'
        else
            print_error "Cannot connect to Ollama API at $OLLAMA_HOST"
            echo "  Fix: Check if Ollama is running"
        fi
        echo ""

        # Check llms.py
        echo -e "${BLUE}=== llms.py Check ===${NC}"
        if command -v llms &> /dev/null; then
            print_success "llms.py installed"
            llms --help | head -1
        else
            print_error "llms.py not found"
            echo "  Fix: pip install llms-py"
            exit 1
        fi

        if pgrep -f "llms.*serve" > /dev/null; then
            print_success "llms.py server running"
        else
            print_error "llms.py server not running"
            echo "  Fix: ./dev-server.sh start"
        fi
        echo ""

        # Check providers
        echo -e "${BLUE}=== Provider Configuration ===${NC}"
        print_status "Checking llms.py provider list..."
        llms ls 2>&1 | head -20
        echo ""

        # Check Ollama specifically
        if llms ls 2>&1 | grep -q "ollama"; then
            print_success "Ollama provider is listed"
        else
            print_warning "Ollama provider not found in llms.py"
            echo "  Fix: llms --enable ollama"
        fi
        echo ""

        # Check config file
        echo -e "${BLUE}=== Configuration Files ===${NC}"
        if [ -f "$HOME/.llms/llms.json" ]; then
            print_success "llms.py config exists"
            echo "  Location: $HOME/.llms/llms.json"
            if grep -q "ollama" "$HOME/.llms/llms.json" 2>/dev/null; then
                print_success "Ollama mentioned in config"
            else
                print_warning "Ollama not in config"
            fi
        else
            print_warning "No llms.py config file"
            echo "  Fix: llms --init"
        fi

        if [ -f "$EXTENSION_DIR/config.json" ]; then
            print_success "Extension config exists"
            echo "  Location: $EXTENSION_DIR/config.json"
        else
            print_warning "No extension config"
        fi
        echo ""

        # Check connectivity
        echo -e "${BLUE}=== Connectivity Test ===${NC}"
        if curl -s "http://localhost:$LLMS_PORT" > /dev/null 2>&1; then
            print_success "Web UI accessible at http://localhost:$LLMS_PORT"
        else
            print_error "Cannot reach web UI"
            echo "  Fix: Check if llms.py server is running"
        fi

        if curl -s "http://localhost:$LLMS_PORT/ext/context_compaction/status" > /dev/null 2>&1; then
            print_success "Extension loaded and responding"
        else
            print_warning "Extension not responding"
        fi
        echo ""

        # Recommendations
        echo -e "${BLUE}=== Recommendations ===${NC}"
        echo "If Ollama models don't appear in llms.py UI:"
        echo "  1. Enable Ollama: llms --enable ollama"
        echo "  2. Check list: llms ls ollama"
        echo "  3. Restart server: ./dev-server.sh restart"
        echo "  4. Check browser console for errors"
        echo ""
        echo "If extension isn't working:"
        echo "  1. Check logs: ./dev-server.sh logs"
        echo "  2. Verify installed: ls -la ~/.llms/extensions/context_compaction"
        echo "  3. Check logs: ./dev-server.sh logs | grep compact"
        ;;

    *)
        echo "Usage: $0 [logs|status|test|diagnose]"
        echo ""
        echo "Commands:"
        echo "  (none)   - Start development environment (Ctrl+C to stop)"
        echo "  logs     - Follow logs in real-time"
        echo "  status   - Check server and provider status"
        echo "  test     - Run quick API test"
        echo "  diagnose - Run full diagnostics (troubleshooting)"
        echo ""
        echo "Troubleshooting:"
        echo "  If Ollama models don't appear in llms:"
        echo "    1. Run: ./dev-server.sh diagnose"
        echo "    2. Enable: llms --enable ollama"
        echo "    3. List providers: llms ls"
        exit 1
        ;;
esac
