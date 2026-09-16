# Trusted publisher diagnostics

When RubyGems rejects release credentials, report only the public GitHub identity
claims and the exchange HTTP status. JWTs, API keys, and response bodies remain
private. This distinguishes identity mismatches from transport failures without
logging credentials.
