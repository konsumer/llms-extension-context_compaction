# Context Compaction Extension for llms

Automatically compacts conversation context when it reaches a configurable threshold, replacing the history with a summary to enable extended conversations on memory-constrained systems.

**Addresses:** [ServiceStack/llms Issue #30](https://github.com/ServiceStack/llms/issues/30) - Context compaction for resource-limited hardware

Perfect for:
- 🖥️ Local Ollama setups with limited GPU memory (4-8GB VRAM)
- ⚡ Long conversations that exceed context windows
- 💰 Reducing API costs by minimizing token usage
- 🔄 Extended coding sessions without losing context

## Features

- **Automatic Monitoring**: Tracks context usage for each conversation using real provider metadata
- **Configurable Threshold**: Trigger compaction at any percentage (default: 80%)
- **Flexible Summarization**: Use any provider/model for generating summaries
- **Customizable Prompts**: Two prompt modes - detailed and simple (for faster models)
- **User Notifications**: Optional in-conversation notifications when compaction occurs
- **RESTful API**: Control compaction settings via HTTP endpoints
- **Preset Configurations**: Ready-to-use configs for Ollama, OpenAI, and Anthropic
- **Resource-Aware**: Optimized for memory-constrained hardware like 8GB GPUs

## Installation

### Quick Start with Presets

**For Ollama users with 8GB GPU:**
```bash
# Install extension
llms --add konsumer/context_compaction

# Use Ollama preset
cp ~/.llms/extensions/context_compaction/presets/ollama-8gb.json \
   ~/.llms/extensions/context_compaction/config.json

# Pull summarization model
ollama pull llama3.2:3b

# Start llms
llms serve
```

**For OpenAI API users:**
```bash
# Install extension
llms --add konsumer/context_compaction

# Use OpenAI preset
cp ~/.llms/extensions/context_compaction/presets/openai.json \
   ~/.llms/extensions/context_compaction/config.json

# Start llms
llms serve
```

### From GitHub

```bash
llms --add konsumer/context_compaction
```

Or if you've cloned the repository:

```bash
llms --add /path/to/context_compaction
```

### Manual Installation

1. Copy this extension to your llms extensions directory:
```bash
mkdir -p ~/.llms/extensions
cp -r /path/to/context_compaction ~/.llms/extensions/context_compaction
```

2. (Optional) Use a preset configuration:
```bash
# For Ollama 8GB
cp ~/.llms/extensions/context_compaction/presets/ollama-8gb.json \
   ~/.llms/extensions/context_compaction/config.json

# For Ollama 4GB
cp ~/.llms/extensions/context_compaction/presets/ollama-4gb.json \
   ~/.llms/extensions/context_compaction/config.json

# For OpenAI
cp ~/.llms/extensions/context_compaction/presets/openai.json \
   ~/.llms/extensions/context_compaction/config.json

# For Anthropic
cp ~/.llms/extensions/context_compaction/presets/anthropic.json \
   ~/.llms/extensions/context_compaction/config.json
```

3. The extension will be automatically loaded when you start llms:
```bash
llms serve
```

To disable the extension, add it to the `disable_extensions` array in your `~/.llms/llms.json`:
```json
{
  "disable_extensions": ["context_compaction"]
}
```

### Ollama Users

See [OLLAMA_GUIDE.md](OLLAMA_GUIDE.md) for detailed setup instructions, model recommendations, and troubleshooting tips specific to resource-constrained hardware.

## Usage

### Configuration File

The extension uses a configuration file located at `~/.llms/extensions/context_compaction/config.json`:

```json
{
  "enabled": true,
  "threshold": 0.8,
  "provider": null,
  "model": null,
  "summary_prompt": "Please provide a comprehensive summary of the conversation so far. Preserve:\n- All critical context and decisions\n- User preferences and constraints\n- Technical details and requirements\n- Code snippets and configurations\n- Conversation flow and key topics\n\nBe thorough but concise. This summary will replace the conversation history."
}
```

Configuration options:

- `enabled` (boolean): Enable/disable context compaction (default: true)
- `threshold` (float): Percentage of context to trigger compaction (0.0-1.0, default: 0.8)
- `provider` (string|null): Provider for summarization (e.g., "openai", "anthropic", "ollama"), null uses current provider
- `model` (string|null): Model for summarization (e.g., "gpt-4o-mini", "claude-3-haiku", "llama3.2:3b"), null uses current model
- `notify_user` (boolean): Add notification message when compaction occurs (default: true)
- `use_simple_prompt` (boolean): Use simpler, faster prompt for summarization (default: false)
- `summary_prompt` (string): Detailed prompt for generating summaries
- `simple_prompt` (string): Brief prompt for fast summarization (used when `use_simple_prompt` is true)

The configuration file is automatically created with defaults on first run if it doesn't exist. You can edit it manually or use the API endpoints to update it.

**Preset configurations** are available in the `presets/` directory for common scenarios. See [presets/README.md](presets/README.md) for details.

### API Endpoints

All endpoints are prefixed with `/ext/context_compaction`:

#### Get Configuration
```bash
curl http://localhost:8000/ext/context_compaction/config
```

#### Update Configuration
```bash
curl -X POST http://localhost:8000/ext/context_compaction/config \
  -H "Content-Type: application/json" \
  -d '{
    "enabled": true,
    "threshold": 0.75,
    "provider": "openai",
    "model": "gpt-4-turbo"
  }'
```

#### Get Status
```bash
curl http://localhost:8000/ext/context_compaction/status
```

#### Trigger Manual Compaction
```bash
curl -X POST http://localhost:8000/ext/context_compaction/compact \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [...],
    "provider": "openai",
    "model": "gpt-4-turbo"
  }'
```

## How It Works

1. **Monitoring**: The extension uses a response filter to track token usage after each LLM response
2. **Detection**: When prompt tokens exceed the configured threshold percentage, compaction is flagged
3. **Summarization**: A summary of the conversation is generated using the specified (or current) provider/model
4. **Replacement**: The conversation history is replaced with:
   - Original system messages
   - The generated summary
   - The last 2 messages for context continuity

## Summary Prompt

The default prompt preserves:
- Critical context and decisions
- User preferences and constraints
- Technical details and requirements
- Code snippets and configurations
- Conversation flow and key topics

You can customize this by modifying the `summary_prompt` field via the API.

## Context Limits

The extension retrieves **actual context limits** from llms' provider metadata using the `provider.model_info()` API. This ensures accurate context tracking for all 530+ supported models across 24 providers.

**How it works:**
1. Extension queries the provider for model metadata
2. Extracts the `limit.context` field from model info
3. Falls back to conservative estimates only if metadata is unavailable

**Example providers and models:**
- OpenAI: GPT-4 Turbo (128K), GPT-4 (8K), GPT-3.5 (4K)
- Anthropic: Claude 3 models (200K), Claude 2 (100K)
- Google: Gemini models (various)
- Local: Llama, Mistral, Mixtral (various)

The extension automatically stays up-to-date as llms' model database is updated daily from models.dev.

## Example

```bash
# Start llms (extension loads automatically)
llms serve

# Configure via config file
cat > ~/.llms/extensions/context_compaction/config.json <<EOF
{
  "enabled": true,
  "threshold": 0.7,
  "provider": "openai",
  "model": "gpt-4-turbo"
}
EOF

# Restart llms to apply changes
llms serve

# Or update configuration via API without restarting
curl -X POST http://localhost:8000/ext/context_compaction/config \
  -H "Content-Type: application/json" \
  -d '{
    "enabled": true,
    "threshold": 0.7,
    "provider": "openai",
    "model": "gpt-4-turbo"
  }'

# Have a long conversation...
# When context reaches 70%, the extension will:
# 1. Detect high usage
# 2. Generate a summary using GPT-4 Turbo
# 3. Replace history with the summary
# 4. Continue the conversation
```

## Troubleshooting

### Compaction Not Triggering

- Check that compaction is enabled in config (`"enabled": true`)
- Verify the threshold is appropriate for your context size
- Check logs for context usage percentages
- Verify the model's context limit is being retrieved (check logs for warnings)

### Summary Quality Issues

- Try using a more capable model for summarization
- Adjust the `summary_prompt` to emphasize what's important
- Consider increasing the threshold to compact less frequently

### Performance Impact

- Summarization adds latency when triggered
- Use a faster model for summarization (e.g., GPT-3.5 Turbo, Claude Haiku)
- Increase the threshold to compact less frequently

## Contributing

Issues and pull requests welcome at: https://github.com/konsumer/context_compaction

## License

MIT
