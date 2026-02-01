"""
LLMS extension for context compaction via /compact command.
Uses llms.py's native API to call configured LLMs.
"""

import json
from pathlib import Path

def __install__(ctx):
    """
    Install hook - registers the /compact command filter.
    """

    # Load configuration
    config_path = Path(__file__).parent / "config.json"
    config = {}

    if config_path.exists():
        with open(config_path, 'r') as f:
            config = json.load(f)

    provider = config.get('provider', 'ollama')
    model = config.get('model', 'qwen2.5:7b')
    summary_prompt = config.get('summary_prompt', 'Summarize this conversation concisely.')

    # Format the full model name as provider/model for llms.py
    full_model = f"{provider}/{model}" if provider else model

    # Store compact boundaries per thread
    compact_boundaries = {}

    async def compact_command_filter(chat, context):
        """Filter that handles /compact command and applies compaction."""

        thread_id = context.get('threadId', 'default')

        if 'messages' not in chat or len(chat['messages']) == 0:
            return

        last_message = chat['messages'][-1]

        if last_message.get('role') != 'user':
            return

        content = last_message.get('content', '')
        text_content = extract_text(content)

        # Check if this is a /compact command
        if text_content and text_content.strip().startswith('/compact'):
            await handle_compact(chat, context, thread_id, full_model, summary_prompt, ctx)
        elif thread_id in compact_boundaries:
            apply_compaction(chat, thread_id, ctx)

    async def handle_compact(chat, context, thread_id, full_model, summary_prompt, ctx):
        """Handle the /compact command."""

        ctx.log(f"[context_compaction] ✓ /compact command (thread: {thread_id})")

        last_message = chat['messages'][-1]
        messages_to_compact = chat['messages'][:-1]

        if len(messages_to_compact) == 0:
            update_text(last_message, "No conversation history to compact.")
            return

        ctx.log(f"[context_compaction] Compacting {len(messages_to_compact)} messages")

        pre_tokens = estimate_tokens(messages_to_compact)
        conversation_text = build_text(messages_to_compact)

        # Generate summary using llms.py's chat_completion API
        summary = await generate_summary(conversation_text, full_model, summary_prompt, ctx)

        if not summary:
            ctx.log(f"[context_compaction] Failed to generate summary")
            update_text(last_message, "Failed to generate summary.")
            return

        ctx.log(f"[context_compaction] ✓ Summary: {len(summary)} chars")

        # Store boundary
        compact_boundaries[thread_id] = {
            'summary': summary,
            'preTokens': pre_tokens,
            'messageCount': len(messages_to_compact)
        }

        # Replace with summary as system message + user's new prompt
        system_msg = {
            "role": "system",
            "content": f"[Context: Previous conversation summary]\n\n{summary}"
        }

        chat['messages'] = [system_msg]
        update_text(last_message, "Continue our conversation. What would you like to discuss next?")
        chat['messages'].append(last_message)

        post_tokens = estimate_tokens(chat['messages'])
        reduction = ((pre_tokens - post_tokens) / pre_tokens * 100) if pre_tokens > 0 else 0
        ctx.log(f"[context_compaction] ✓ Reduction: ~{reduction:.0f}% ({pre_tokens} -> {post_tokens})")

    def apply_compaction(chat, thread_id, ctx):
        """Apply existing compaction to current request."""

        boundary = compact_boundaries[thread_id]
        original_count = len(chat['messages'])

        # System message with summary
        system_msg = {
            "role": "system",
            "content": f"[Context: Previous conversation summary]\n\n{boundary['summary']}"
        }

        # Keep only the latest user message
        recent = chat['messages'][-1:]

        chat['messages'] = [system_msg] + recent

        ctx.log(f"[context_compaction] Applied: {original_count} -> {len(chat['messages'])} messages")

    def extract_text(content):
        """Extract text from message content."""
        if isinstance(content, list) and len(content) > 0:
            if isinstance(content[0], dict):
                return content[0].get('text', '')
            return str(content[0])
        return str(content)

    def update_text(message, text):
        """Update message text."""
        content = message.get('content', '')
        if isinstance(content, list) and len(content) > 0 and isinstance(content[0], dict):
            content[0]['text'] = text
        else:
            message['content'] = text

    def build_text(messages):
        """Build conversation text."""
        text = ""
        for msg in messages:
            role = msg.get('role', 'unknown')
            content = msg.get('content', '')

            if isinstance(content, list):
                parts = []
                for p in content:
                    if isinstance(p, dict):
                        parts.append(p.get('text', ''))
                    else:
                        parts.append(str(p))
                content = ' '.join(parts)
            else:
                content = str(content)

            text += f"{role}: {content}\n\n"

        return text

    def estimate_tokens(messages):
        """Estimate tokens (4 chars ≈ 1 token)."""
        total = 0
        for msg in messages:
            content = msg.get('content', '')
            if isinstance(content, (dict, list)):
                content = json.dumps(content)
            total += len(str(content))
        return total // 4

    async def generate_summary(conversation_text, full_model, prompt, ctx):
        """
        Generate summary using llms.py's chat_completion API.
        This uses whatever provider/model is configured in llms.py.
        """
        try:
            # Create a chat request using llms.py's API
            summary_chat = ctx.chat_request(
                model=full_model,
                system_prompt=prompt,
                text=conversation_text
            )

            ctx.log(f"[context_compaction] Calling LLM: {full_model}")

            # Use llms.py's chat_completion to call the configured LLM
            response = await ctx.chat_completion(summary_chat)

            # Extract the summary from the response
            if response and 'choices' in response and len(response['choices']) > 0:
                summary = response['choices'][0]['message']['content']
                return summary.strip()
            else:
                ctx.log(f"[context_compaction] Unexpected response format")
                return None

        except Exception as e:
            ctx.log(f"[context_compaction] Error: {e}")
            return None

    ctx.register_chat_request_filter(compact_command_filter)
    ctx.log("[context_compaction] Extension loaded")
