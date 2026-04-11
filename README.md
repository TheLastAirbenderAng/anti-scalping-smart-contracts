# Anti-Scalping Smart Contracts

> **GROUP 4 - Ang, Katigbak, Garrovillo, Ong, Pintor**
>
> **Project:** Decentralized Event Ticketing and Anti-Scalping Protocol
>
> **Problem:** The current event ticketing industry is severely compromised by predatory scalping and fraudulent resales. Automated bots rapidly purchase large quantities of tickets for concerts and university events, creating artificial scarcity and driving up prices on secondary markets. Consequently, buyers are forced to pay exorbitant markups or risk falling victim to scams involving forged or duplicated QR codes, with no centralized way to verify ticket authenticity.
>
> **Why Blockchain and Smart Contracts are Important for this Problem:** By converting event tickets into digital assets governed by smart contracts, we can establish a trustless, transparent system that directly addresses fraud and price manipulation via immutable authenticity and automate price ceilings. For the former, the blockchain serves as the ultimate, tamper-proof public ledger. Because ticket ownership is cryptographically tied to a user's wallet address and verified by the smart contract, it is impossible to generate fake tickets or sell duplicate copies. For price ceilings, smart contracts allow us to program strict economic rules directly into the asset's code. By utilizing custom transfer functions and conditional `require` statements, the contract can dictate that a ticket cannot be transferred to a new owner if the transaction value exceeds a predefined cap (e.g., 110% of the original base price). This algorithmically enforces fair pricing and effectively eliminates the profit incentive for scalping bots.

A Solidity protocol that eliminates ticket fraud and predatory scalping by turning every event ticket into an individual smart contract with enforced price ceilings.

## The Problem

The event ticketing industry faces two systemic issues:

1. **Scalping** - Bots buy tickets in bulk and resell them on secondary markets at massive markups, creating artificial scarcity and pricing out genuine attendees.
2. **Fraud** - Buyers on secondary markets risk purchasing fake or duplicate tickets (e.g., copied QR codes) with no reliable way to verify authenticity.

## The Solution

This protocol issues every ticket as its own deployed smart contract on the blockchain. This provides:

- **Immutable Authenticity** - Ownership is cryptographically tied to a wallet address. The contract address is unique and cannot be duplicated.
- **Enforced Price Ceilings** - A `require` statement mathematically caps the resale price at 110% of the original price, removing the profit incentive for scalpers.
- **Transparent Payment Routing** - Funds flow directly from buyer to seller with no intermediary.
- **On-Chain Auditability** - Every action (creation, listing, sale, transfer, cancellation) emits events that can be monitored off-chain.

---

## Architecture

The protocol consists of two Solidity contracts that work together using a **factory pattern**:

### `EventOrganizer` (Factory Contract)

The central hub, acting as the box office. It is responsible for deploying and tracking all ticket contracts.

| State | Type | Description |
|---|---|---|
| `organizer` | `address` | The deployer, permanently recorded as the event organizer |
| `allTickets` | `Ticket[]` | Master list of all deployed ticket contract addresses |
| `currentEventName` | `string` | Name of the current event |
| `eventCancelled` | `bool` | Whether the event has been cancelled |

| Function | Access | Description |
|---|---|---|
| `createTicket(_eventName, _price)` | Organizer only | Deploys a new `Ticket` child contract and registers it |
| `createTickets(_eventName, _price, _count)` | Organizer only | Batch-deploys up to 50 `Ticket` contracts in one transaction |
| `cancelEvent()` | Organizer only | Cancels the event, marks all tickets as cancelled, and refunds buyers |
| `getDeployedTickets()` | Public | Returns the full array of all ticket contracts |
| `getTicketCount()` | Public | Returns the total number of tickets |

### `Ticket` (Child Contract)

Each deployed instance represents a single, programmable digital ticket.

| State | Type | Description |
|---|---|---|
| `currentOwner` | `address` | The wallet that currently holds the ticket |
| `eventOrganizer` | `address` | The parent factory contract that created this ticket |
| `originalPrice` | `uint256` | The initial sale price (in Wei) |
| `maxResalePrice` | `uint256` | Hardcoded to 110% of `originalPrice` |
| `status` | `Status` | Current lifecycle state (see enum below) |
| `salePrice` | `uint256` | The price the owner has listed it for |

### Ticket Status Enum

```
Available  -> Ticket exists, owned by organizer, not yet listed
ForSale    -> Owner has listed it on the secondary market
Sold       -> Ticket has been purchased (resting state between resales)
Cancelled  -> Event was cancelled; ticket is no longer valid
```

### Events

| Event | Emitted When | Key Parameters |
|---|---|---|
| `TicketCreated` | A new ticket contract is deployed | `ticketAddress`, `eventName`, `originalPrice` |
| `TicketListed` | Owner lists a ticket for sale | `ticketAddress`, `salePrice` |
| `TicketSold` | Ownership changes hands (sale or gift) | `ticketAddress`, `from`, `to`, `price` |
| `EventCancelled` | Organizer cancels the entire event | `eventName`, `ticketCount` |

| Function | Access | Description |
|---|---|---|
| `listForSale(_price)` | Owner only | Lists the ticket for resale; reverts if price exceeds 110% of original |
| `unlistForSale()` | Owner only | Takes the ticket off the market |
| `buyTicket()` | Anyone (payable) | Purchases a listed ticket; transfers ownership and routes payment |
| `transferTicket(_newOwner)` | Owner only | Gifts the ticket to another address for free |
| `cancelTicket()` | Factory only | Marks the ticket as cancelled |
| `refundBuyer()` | Factory only | Refunds `originalPrice` to the current buyer after cancellation |

---

## How It Works

### Phase 1: Setting Up the Box Office

The event organizer deploys the `EventOrganizer` factory contract. The blockchain records the deployer's address as the permanent `organizer`.

### Phase 2: Minting Tickets

The organizer calls `createTicket()` for individual tickets, or `createTickets()` to batch-mint up to 50 tickets in a single transaction. Each call deploys a brand new `Ticket` child contract. The factory's `allTickets` array tracks every deployed address.

At this point, the `currentOwner` of every ticket is the organizer and `status` is `Available`.

### Phase 3: Primary Sale

The organizer calls `listForSale()` on each ticket at the base price. A buyer calls `buyTicket()` on a specific ticket contract, sending the exact `msg.value`.

The contract verifies the payment, transfers ownership to the buyer, forwards the funds to the previous owner, and updates `status` to `Sold`.

### Phase 4: Resale (Anti-Scalping Enforcement)

If a ticket holder attempts to resell at a markup (e.g., listing a 1,000 Wei ticket for 2,000 Wei), the contract hits this check:

```solidity
require(_price <= maxResalePrice, "Price exceeds 110% anti-scalping limit!");
```

Since `maxResalePrice` was calculated as 1,100 Wei (110% of 1,000) at deployment, the transaction instantly reverts. The seller can only list at or below that ceiling.

### Phase 5: Free Transfer (Gifting)

A ticket holder can call `transferTicket(address)` to gift their ticket to someone else without any payment. The ticket must not be currently listed for sale or cancelled. This covers the use case of giving a ticket to a friend.

### Phase 6: Event Cancellation and Refund

If the event is cancelled, the organizer calls `cancelEvent()` on the factory. The factory iterates through every ticket:
1. Calls `cancelTicket()` to mark it as `Cancelled`
2. Calls `refundBuyer()` to send `originalPrice` back to the current holder

The factory must hold enough balance to cover refunds. Primary sale proceeds accumulate in the factory automatically. Refunds are issued at `originalPrice`, not the resale price.

---

## Quick Start with Remix IDE

1. Open [Remix IDE](https://remix.ethereum.org).
2. Import or paste `TicketProtocol.sol` into a new file.
3. Go to the **Solidity Compiler** tab and compile with `^0.8.20`.
4. Go to **Deploy & Run Transactions**.
5. Deploy the `EventOrganizer` contract.
6. **Batch mint tickets:** Call `createTickets("My Event", 1000, 5)` to create 5 tickets.
7. **List a ticket:** Copy the address from `allTickets(0)`, expand it in Remix, and call `listForSale(1000)`.
8. **Buy a ticket:** Switch to a different account and call `buyTicket()` on that ticket, sending exactly 1000 Wei.
9. **Gift a ticket:** From the buyer account, call `transferTicket()` with a friend's address.
10. **Cancel the event:** Switch back to the organizer and call `cancelEvent()` to cancel and refund all buyers.

---

## Gas Considerations

- **Batch limit of 50 tickets** prevents gas exhaustion in a single transaction. Each ticket deployment costs approximately 200k-300k gas.
- **Event cancellation** loops through all tickets. Suitable for Remix's JavaScript VM and small events. For production, a pull-pattern (buyers claim their own refund) would be needed at scale.

---

## Tech Stack

- **Language:** Solidity `^0.8.20`
- **IDE:** Remix IDE
- **License:** MIT

---

## Future Work

- Build a web frontend (React) to abstract contract interactions behind a standard ticketing UI.
- Implement ERC-721 compatibility for broader wallet and marketplace support.
- Add ticket metadata (seat number, tier, event date) to each `Ticket` contract.
- Restructure into a single contract with structs and mappings for lower gas costs at scale.
- Implement pull-pattern refunds for cancellation at production scale.
