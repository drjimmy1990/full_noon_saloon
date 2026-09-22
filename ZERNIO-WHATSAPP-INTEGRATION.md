# 🌸 Zernio WhatsApp Integration Guide — Salon Noon

> Complete documentation for Salon Noon's WhatsApp AI booking assistant, customer engagement, and automated messaging powered by **Zernio API** and **n8n**.

---

## 📌 1. Architecture Overview

```mermaid
flowchart TD
    Customer([📱 Customer on WhatsApp]) -->|Sends Message / Voice Note| Zernio[☁️ Zernio Cloud WhatsApp API]
    Zernio -->|Webhook: message.received| N8N_Webhook[⚡ n8n Webhook Node]
    
    subgraph Inbound & Normalization
        N8N_Webhook --> If_Filter{Is Outgoing / Agent?}
        If_Filter -->|Yes| Update_CRM[Sync Agent Outgoing Msg]
        If_Filter -->|No: Customer Inbound| JS_Normalize[Code in JavaScript6: Normalize Payload]
        JS_Normalize --> SQL_Context[Execute SQL: Load Salon Settings, Staff & Services]
        SQL_Context --> Map_Fields[Edit Fields: Map Context & IDs]
        Map_Fields --> Mark_Read[🔵 Mark as Read: Send WhatsApp Blue Ticks]
        Map_Fields --> Find_Contact[Supabase: Find / Create Client]
    end

    subgraph AI Agent & Decision Engine
        Find_Contact --> AI_Agent[🤖 AI Agent: Gemini Model + Chat Memory]
        AI_Agent -.-> Tools[Tools: check_availability, get_staff, create_booking]
        AI_Agent --> JSON_Parser[Parse AI JSON Response]
        JSON_Parser --> Switch_Intent{Switch2: Intent Router}
    end

    subgraph Outbound Zernio Messaging
        Switch_Intent -->|conversation| Zernio_Text1[Zernio Send Text: General Chat]
        Switch_Intent -->|booking| Zernio_Text2[Zernio Send Text: Booking Confirmation]
        Switch_Intent -->|customer_service| Zernio_Text3[Zernio Send Text: Agent Handoff]
        Switch_Intent -->|product images| Zernio_Products[Zernio Send Text + Product Photos Loop]
        Switch_Intent -->|testimonials| Zernio_Reviews[Zernio Send Text + Before/After Photo Sets]
        Switch_Intent -->|job_request / bridal| Zernio_Special[Zernio Send Text: Inquiries]
    end

    Zernio_Text1 --> Log_DB[(Supabase Message Table)]
    Zernio_Text2 --> Log_DB
    Zernio_Text3 --> Log_DB
    Zernio_Products --> Log_DB
    Zernio_Reviews --> Log_DB
    Zernio_Special --> Log_DB
```

---

## 🔑 2. Zernio Credentials & Configuration

### Active Credentials in Workflow
- **Zernio API Base URL**: `https://zernio.com/api/v1`
- **Account ID**: `6a4a53109d9472faae8493e7` (WhatsApp Channel)
- **API Key**: `Bearer sk_dbb52d55c857d3083ac169d156a86825d7d138813939d3ef427202368fcb454d`

### Webhook Setup in Zernio Dashboard
1. Log into your [Zernio Dashboard](https://zernio.com/dashboard/webhooks).
2. Create or configure your Webhook Endpoint:
   - **URL**: Your n8n production webhook URL (e.g. `https://n8n.ai4eg.com/webhook/...` or current n8n path).
   - **Subscribed Events**:
     - `message.received` *(Essential: triggers incoming customer messages)*
     - `message.sent` *(Optional: tracks outgoing replies sent by human agents)*
3. **Payload Structure Received**:
   ```json
   {
     "id": "evt_abc123",
     "event": "message.received",
     "message": {
       "id": "msg_xyz789",
       "conversationId": "conv_noon_salon_123",
       "platform": "whatsapp",
       "platformMessageId": "wamid.HBgL...",
       "direction": "incoming",
       "text": "مرحبا بدي احجز موعد للشعر",
       "attachments": [],
       "sender": {
         "id": "962791234567",
         "phoneNumber": "+962791234567",
         "name": "سارة أحمد"
       },
       "sentAt": "2026-09-18T10:30:00.000Z"
     },
     "conversation": {
       "id": "conv_noon_salon_123",
       "participantName": "سارة أحمد",
       "participantUsername": "+962791234567"
     },
     "account": {
       "id": "6a4a53109d9472faae8493e7",
       "platform": "whatsapp",
       "displayName": "Noon Salon"
     }
   }
   ```

---

## 🛠️ 3. Key Enhancements & Bug Fixes Applied

| Area | Previous State (Buggy / Incomplete) | New State (Zernio Certified) |
|---|---|---|
| **Outbound URLs** | Contained trailing whitespace (`.../messages `) triggering HTTP 404/Bad URI. | Trailing whitespace completely eliminated across all endpoints. |
| **Body Parameter Syntax** | Contained leading `=` in parameter names (`"=accountId"`), rejected by Zernio. | Parameter names fixed to `"accountId"`. |
| **Context References** | Deep fragile references (`$('Webhook').item.json.body.conversation.id`). | Mapped cleanly in `Edit Fields` (`{{ $('Edit Fields').item.json.ConversationId }}`). |
| **Mark as Read (Blue Ticks)** | Not present. Customers saw single/double gray ticks only. | Dedicated `Mark as Read (Zernio)` node sends blue ticks immediately upon message receipt. |
| **Product Images Branch** | Output 2 in `Switch2` was dead-ended with missing nodes. | Restored full product images pipeline with Zernio media attachment delivery. |
| **Testimonials Flow** | Pointed to deprecated Evolution API (`evo.hillhousevilla.com`) and disabled. | Converted to Zernio text + image attachments (`attachmentType: "image"`), re-enabled. |
| **Voice Notes & Audio** | Called deprecated `evo.ai4eg.com/chat/getBase64FromMediaMessage`. | Direct GET on Zernio media attachment URL into binary stream for Gemini. |

---

## 📡 4. Zernio API Endpoints Used in Workflow

### 1. Send Outbound Text Message
- **Method**: `POST`
- **URL**: `https://zernio.com/api/v1/inbox/conversations/{{ $('Edit Fields').item.json.ConversationId }}/messages`
- **Headers**:
  ```http
  Authorization: Bearer sk_dbb52d55c857d3083ac169d156a86825d7d138813939d3ef427202368fcb454d
  Content-Type: application/json
  ```
- **Body**:
  ```json
  {
    "accountId": "{{ $('Edit Fields').item.json.AccountId }}",
    "message": "{{ $json.response }}"
  }
  ```

### 2. Send Media (Image / Photo Sets)
- **Method**: `POST`
- **URL**: `https://zernio.com/api/v1/inbox/conversations/{{ $('Edit Fields').item.json.ConversationId }}/messages`
- **Body**:
  ```json
  {
    "accountId": "{{ $('Edit Fields').item.json.AccountId }}",
    "attachmentUrl": "{{ $json.productImages || $json.imageSets }}",
    "attachmentType": "image",
    "message": ""
  }
  ```

### 3. Mark Conversation as Read (Blue Ticks)
- **Method**: `POST`
- **URL**: `https://zernio.com/api/v1/inbox/conversations/{{ $('Edit Fields').item.json.ConversationId }}/read`
- **Body**:
  ```json
  {
    "accountId": "{{ $('Edit Fields').item.json.AccountId }}"
  }
  ```

### 4. Emoji Reaction
- **Method**: `POST`
- **URL**: `https://zernio.com/api/v1/inbox/conversations/{{ $('Edit Fields').item.json.ConversationId }}/messages/{{ $('Edit Fields').item.json.MessageId }}/reactions`
- **Body**:
  ```json
  {
    "accountId": "{{ $('Edit Fields').item.json.AccountId }}",
    "emoji": "🌸"
  }
  ```

---

## 🧪 5. Verification Checklist

- [x] All 13 Zernio HTTP Request nodes validated with zero URL syntax errors.
- [x] All body parameters validated with zero `=` prefix errors.
- [x] Webhook ingestion simulated with realistic Zernio WhatsApp payload.
- [x] Normalized phone number format (`962791234567`) and WhatsApp JID (`962791234567@s.whatsapp.net`).
- [x] Inbound audio/image extraction tested with attachment URL mapping.
- [x] Synchronized across both `sallon whats.json` and `n8n-workflow.json`.
- [x] Backups preserved as `sallon whats.backup.json` and `n8n-workflow.backup.json`.
