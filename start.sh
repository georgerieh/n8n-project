#!/bin/bash

# 1. Load variables from .env file
if [ -f .env ]; then
    # Automatically export all variables defined in .env
    set -a
    source .env
    set -b
else
    echo "Error: .env file not found!"
    exit 1
fi

# Verify TELEGRAM_BOT_TOKEN exists
if [ -z "$TELEGRAM_BOT_TOKEN" ]; then
    echo "Error: TELEGRAM_BOT_TOKEN is not defined in .env file."
    exit 1
fi

# 2. Start cloudflared
docker compose up -d cloudflared

echo "Waiting for Cloudflare Tunnel to connect and publish URL..."

TUNNEL_URL=""
for i in {1..30}; do
    # Ensure cloudflared logged success/registered connections
    LOGS=$(docker compose logs cloudflared 2>&1)
    
    if echo "$LOGS" | grep -q "Registered tunnel connection"; then
        TUNNEL_URL=$(echo "$LOGS" | grep -o 'https://[a-zA-Z0-9-]*\.trycloudflare\.com' | tail -n 1)
        if [ -n "$TUNNEL_URL" ]; then
            break
        fi
    fi
    sleep 1
done

if [ -z "$TUNNEL_URL" ]; then
    echo "Error: Could not extract Cloudflare Tunnel URL within 30 seconds."
    exit 1
fi

# Short delay to allow global DNS edge sync
sleep 3

echo "Generated Tunnel URL: $TUNNEL_URL"

# 3. Update WEBHOOK_URL in .env (Cross-platform sed fix)
if grep -q "^WEBHOOK_URL=" .env 2>/dev/null; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|^WEBHOOK_URL=.*|WEBHOOK_URL=${TUNNEL_URL}/|" .env
    else
        sed -i "s|^WEBHOOK_URL=.*|WEBHOOK_URL=${TUNNEL_URL}/|" .env
    fi
else
    echo "WEBHOOK_URL=${TUNNEL_URL}/" >> .env
fi

# 4. Start/restart n8n to pick up the updated WEBHOOK_URL
docker compose up -d n8n

echo "--------------------------------------------------------"
echo "n8n started successfully with WEBHOOK_URL=${TUNNEL_URL}/"
echo "--------------------------------------------------------"

# 5. Automatically register Webhook with Telegram API
WEBHOOK_ENDPOINT="${TUNNEL_URL}/webhook/b2583859-06e7-4953-adc2-9d7d65a3121a/webhook"

echo "Registering Webhook with Telegram..."
RESPONSE=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/setWebhook?url=${WEBHOOK_ENDPOINT}")

echo "Telegram Response: $RESPONSE"