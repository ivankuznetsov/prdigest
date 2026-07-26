# Remove deterministic delivery mode

- Removed `prdigest run`, the `serve` stub, deterministic Telegram rendering,
  schedule/cursor state, catch-up logic, and the `prdigest-result` envelope.
- Kept `prdigest facts` as the deterministic contract for OpenClaw and other
  agents.
- Made `prdigest prose --deliver` the packaged systemd and container default.
- Changed provider-written Telegram delivery to plain text with no HTML
  `parse_mode`, while retaining checkpointed replay and safe control-character
  rejection.
- Simplified configuration to repository facts, provider settings, Telegram
  delivery, and `state.delivery_path`.
