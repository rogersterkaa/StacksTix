# StacksTix — Bitcoin-Secured NFT Ticketing Protocol

[![Clarity](https://img.shields.io/badge/Clarity-3.0-blue)](https://clarity-lang.org/)
[![Tests](https://img.shields.io/badge/Tests-20%20passing-success)](https://github.com/rogersterkaa/StacksTix)
[![SIP-009](https://img.shields.io/badge/SIP--009-Compliant-green)](https://github.com/stacksgov/sips)

A decentralized, open-source ticketing protocol built on the **Stacks blockchain** that enables event organizers to issue, manage, and verify tickets as **Bitcoin-secured NFTs**.

## Built on Stacks. Secured by Bitcoin. ⚡

---

## 🎯 Problem & Solution

### The Problem
Traditional ticketing platforms are centralized, opaque, prone to fraud, and enable scalping.

### The StacksTix Solution
- ✅ **Bitcoin-secured** via Stacks blockchain
- ✅ **SIP-009 compliant** NFT tickets
- ✅ **Anti-scalping** with price caps
- ✅ **True ownership** for ticket holders
- ✅ **Open-source** and auditable

---

## 🚀 Quick Start
```bash
git clone https://github.com/rogersterkaa/StacksTix.git
cd StacksTix
npm install
clarinet check
npm test
```

---

## 📦 Core Features

1. **Event Management** - Create ticketed events with pricing and policies
2. **NFT Tickets (SIP-009)** - Each ticket is a Bitcoin-secured NFT
3. **Anti-Scalping** - Enforce maximum resale prices
4. **Ticket Validation** - Mark tickets as used at event entry
5. **Revenue Management** - Automatic payment splitting

---

## 🏗️ Architecture

Two-contract design for security:
- **stackstix-logic.clar** - Public API and business logic
- **stackstix-storage.clar** - Data storage layer

---

## 📖 API Reference

### create-event
Creates a new ticketed event.
```clarity
(contract-call? .stackstix-logic create-event
  u"Bitcoin 2026 Conference"
  u"Annual summit"
  u"Lagos, Nigeria"
  u1000  ;; start block
  u1100  ;; end block
  u50000000  ;; 50 STX per ticket
  u500  ;; 500 tickets
  true  ;; refunds allowed
  true  ;; transferable
  none  ;; metadata URI
)
```

### purchase-ticket
Buys a ticket (mints SIP-009 NFT).
```clarity
(contract-call? .stackstix-logic purchase-ticket u1)
```

### transfer (SIP-009)
Transfers ticket ownership.
```clarity
(contract-call? .stackstix-logic transfer
  u1  ;; ticket-id
  tx-sender  ;; sender
  'ST1...  ;; recipient
)
```

### set-transfer-restriction
Enforces anti-scalping price caps.
```clarity
(contract-call? .stackstix-logic set-transfer-restriction
  u1  ;; ticket-id
  true  ;; transferable
  (some u150000000)  ;; max 150 STX
  none  ;; no time lock
)
```

---

## 💻 Integration with Stacks.js
```typescript
import { openContractCall } from '@stacks/connect';
import { uintCV, stringUtf8CV, boolCV, noneCV } from '@stacks/transactions';

// Purchase a ticket
await openContractCall({
  contractAddress: 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM',
  contractName: 'stackstix-logic',
  functionName: 'purchase-ticket',
  functionArgs: [uintCV(1)],
});
```

---

## 🧪 Testing
```bash
npm test
```

**20 tests passing:**
- 14 core functionality tests
- 3 anti-scalping tests
- 3 contract tests

---

## 📊 Gas Costs

| Operation | Cost |
|-----------|------|
| Create event | ~15,000 units |
| Purchase ticket | ~25,000 units |
| Transfer | ~8,000 units |
| Validate | ~6,000 units |

---

## 🗺️ Roadmap

### ✅ Completed
- SIP-009 NFT implementation
- Anti-scalping enforcement
- 20-test suite

### 🔄 In Progress
- Multi-tier tickets (VIP/GA)
- Refund mechanism
- Testnet deployment

---

## 📄 License

MIT

---

**Built on Stacks. Secured by Bitcoin.** ⚡
