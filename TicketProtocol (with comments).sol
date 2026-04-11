// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 * ============================================================
 *  ANTI-SCALPING SMART CONTRACT PROTOCOL
 * ============================================================
 *
 *  This file contains TWO contracts that work together:
 *
 *  1. Ticket        - Each deployed instance represents ONE ticket.
 *                     It handles listing, buying, transferring, and
 *                     cancellation for that specific ticket.
 *
 *  2. EventOrganizer - The "box office" or factory contract.
 *                     It creates (mints) Ticket contracts, tracks
 *                     all of them, and manages event-wide actions
 *                     like cancellation and refunds.
 *
 *  PATTERN USED: Factory Pattern
 *  - The EventOrganizer deploys multiple Ticket child contracts.
 *  - This is the same pattern used in our CondoLeaseContract project,
 *    where LeaseFactoryContract creates individual LeaseContracts.
 *
 *  KEY CONCEPTS DEMONSTRATED:
 *  - Modifiers (onlyOwner, onlyOrganizer)
 *  - Enums (Status: Available, ForSale, Sold, Cancelled)
 *  - Events (TicketCreated, TicketListed, TicketSold, EventCancelled)
 *  - Payable functions and value transfers
 *  - Factory pattern (parent creates children)
 *  - Access control via require statements
 *  - Anti-scalping price ceiling enforcement
 *
 * ============================================================
 */


// ============================================================
//  TICKET CONTRACT - One instance per ticket
// ============================================================

/// @title Individual Event Ticket Contract
contract Ticket {

    // ----- STATE VARIABLES -----
    // These store the permanent data for this ticket on the blockchain.

    address public currentOwner;      // Who currently holds this ticket
    address public eventOrganizer;    // The factory contract that created this ticket
    string public eventName;          // Name of the event (e.g., "UAAP Finals")
    uint256 public originalPrice;     // The initial price when first sold (in Wei)
    uint256 public maxResalePrice;    // The maximum allowed resale price (110% of original)

    // ----- ENUM: Ticket Status -----
    // Instead of using a simple true/false (bool), we use an enum to track
    // the exact lifecycle stage of the ticket. This is the same concept as
    // the Status enum in CondoLeaseContract (PENDING, PAID, TERMINATED).
    //
    // Available  -> Just created, owned by organizer, not yet listed for sale
    // ForSale    -> Owner has listed it on the market at a specific price
    // Sold       -> Has been purchased at least once (resting state between resales)
    // Cancelled  -> Event was cancelled; ticket is no longer usable (terminal state)
    enum Status { Available, ForSale, Sold, Cancelled }
    Status public status;

    uint256 public salePrice;  // Only meaningful when status is ForSale


    // ----- EVENTS -----
    // Events are logs stored on the blockchain that external applications
    // (like a React website) can listen to. They don't cost gas to store
    // and are the standard way to track what happened in a transaction.
    //
    // "indexed" parameters allow filtering (e.g., "show me all events for ticket X")

    /// @dev Emitted when a ticket is listed for sale
    event TicketListed(address indexed ticketAddress, uint256 salePrice);

    /// @dev Emitted when ownership changes (via sale OR free transfer)
    /// @param price is 0 for free transfers, actual price for sales/refunds
    event TicketSold(address indexed ticketAddress, address indexed from, address indexed to, uint256 price);


    // ----- MODIFIERS -----
    // Modifiers are reusable conditions that can be applied to functions.
    // The "_;" is a placeholder for the function body.
    // If the require fails, the entire transaction reverts.

    /// @dev Only the current ticket holder can call this function
    modifier onlyOwner() {
        require(msg.sender == currentOwner, "Not the ticket owner");
        _;
    }


    // ----- CONSTRUCTOR -----
    // Runs ONCE when this ticket contract is deployed (called by the factory).

    /// @param _eventName    Name of the event
    /// @param _originalPrice Base price in Wei (1 ETH = 10^18 Wei)
    /// @param _organizer    Address of the EventOrganizer factory contract
    constructor(string memory _eventName, uint256 _originalPrice, address _organizer) {
        eventOrganizer = _organizer;
        currentOwner = _organizer;  // The organizer (factory) owns the ticket first
        eventName = _eventName;
        originalPrice = _originalPrice;

        // ANTI-SCALPING MATH: Cap resale at 110% of the original price.
        // Example: If original price is 1000 Wei, max resale = 1000 + (1000 * 10 / 100) = 1100 Wei.
        // This is calculated ONCE at deployment and can never be changed.
        maxResalePrice = _originalPrice + (_originalPrice * 10 / 100);

        status = Status.Available;  // Start as available for the organizer to list
    }


    // ----- CORE FUNCTIONS -----

    /// @notice List this ticket for sale at a specified price
    /// @param _price The price the owner wants to sell for (in Wei)
    /// @dev This is where anti-scalping is enforced. If _price exceeds
    ///      maxResalePrice (110% of original), the transaction REVERTS.
    function listForSale(uint256 _price) external onlyOwner {
        // Can only list if Available (never sold) or Sold (was sold before)
        require(status == Status.Available || status == Status.Sold, "Ticket not listable");

        // CORE ANTI-SCALPING CHECK: This single line kills the scalper business model.
        // If someone tries to list at double the price, it fails instantly.
        require(_price <= maxResalePrice, "Price exceeds 110% anti-scalping limit!");

        salePrice = _price;
        status = Status.ForSale;
        emit TicketListed(address(this), _price);
    }

    /// @notice Take the ticket off the market (owner changed their mind)
    /// @dev Returns status to Sold (the resting state after first purchase)
    function unlistForSale() external onlyOwner {
        require(status == Status.ForSale, "Ticket is not listed for sale");
        status = Status.Sold;
        salePrice = 0;
    }

    /// @notice Buy this ticket by sending the exact payment
    /// @dev The buyer calls this function and sends ETH via msg.value.
    ///      SECURITY: All state changes happen BEFORE the external call
    ///      (the .call that sends money). This prevents reentrancy attacks.
    function buyTicket() external payable {
        require(status == Status.ForSale, "Ticket is not currently for sale");
        require(msg.value == salePrice, "Incorrect payment amount");

        address previousOwner = currentOwner;

        // Step 1: Update state (ownership transfer + status change)
        currentOwner = msg.sender;
        status = Status.Sold;

        // Step 2: Send the money to the previous owner
        // Using .call{} instead of .transfer() or .send() because it is
        // the recommended method in modern Solidity (same as CondoLeaseContract).
        (bool sent, ) = payable(previousOwner).call{value: msg.value}("");
        require(sent, "Payment transfer failed");

        // Step 3: Emit event after everything succeeds
        emit TicketSold(address(this), previousOwner, msg.sender, msg.value);
    }

    /// @notice Gift/transfer this ticket to someone else for free
    /// @param _newOwner The wallet address of the recipient
    /// @dev This covers the real-world case of giving your ticket to a friend.
    ///      The ticket must NOT be currently listed for sale or cancelled.
    function transferTicket(address _newOwner) external onlyOwner {
        require(status != Status.Cancelled, "Cannot transfer a cancelled ticket");
        require(status != Status.ForSale, "Unlist the ticket before transferring");
        require(_newOwner != address(0), "Cannot transfer to zero address");
        require(_newOwner != msg.sender, "Cannot transfer to yourself");

        address previousOwner = currentOwner;
        currentOwner = _newOwner;

        // Price is 0 to distinguish gifts from sales in event logs
        emit TicketSold(address(this), previousOwner, _newOwner, 0);
    }


    // ----- CANCELLATION FUNCTIONS -----
    // These are called by the factory contract during event cancellation.
    // They are NOT called directly by users.

    /// @notice Mark this ticket as cancelled (called by factory only)
    /// @dev Checks msg.sender against eventOrganizer (which is the factory address)
    function cancelTicket() external {
        require(msg.sender == eventOrganizer, "Only organizer can cancel");
        require(status != Status.Cancelled, "Already cancelled");
        status = Status.Cancelled;
    }

    /// @notice Refund the current buyer after cancellation (called by factory only)
    /// @dev Sends originalPrice back to whoever currently holds the ticket.
    ///      Refund is at originalPrice (not resale price) — this is a deliberate
    ///      design choice for fairness and simplicity.
    function refundBuyer() external {
        require(msg.sender == eventOrganizer, "Only organizer can refund");
        require(status == Status.Cancelled, "Ticket must be cancelled first");

        // If the ticket was never sold (still owned by organizer), no one to refund — skip
        if (currentOwner == eventOrganizer) {
            return;
        }

        address payable refundRecipient = payable(currentOwner);
        uint256 refundAmount = originalPrice;

        // Return ownership to the organizer
        currentOwner = eventOrganizer;

        // Send the refund
        (bool sent, ) = refundRecipient.call{value: refundAmount}("");
        require(sent, "Refund transfer failed");

        emit TicketSold(address(this), refundRecipient, eventOrganizer, refundAmount);
    }
}


// ============================================================
//  EVENT ORGANIZER CONTRACT - The "Box Office" / Factory
// ============================================================

/// @title Factory Contract to Generate and Manage Tickets
contract EventOrganizer {

    // ----- STATE VARIABLES -----

    Ticket[] public allTickets;       // Array of all deployed Ticket contract addresses
    address public organizer;         // The person who deployed this factory
    string public currentEventName;   // Name of the event being managed
    bool public eventCancelled;       // Flag to prevent new tickets after cancellation


    // ----- EVENTS -----

    /// @dev Emitted every time a new Ticket contract is deployed
    event TicketCreated(address indexed ticketAddress, string eventName, uint256 originalPrice);

    /// @dev Emitted when the organizer cancels the entire event
    event EventCancelled(string eventName, uint256 ticketCount);


    // ----- MODIFIERS -----

    /// @dev Only the person who deployed this factory can call restricted functions
    modifier onlyOrganizer() {
        require(msg.sender == organizer, "Only organizer can do this");
        _;
    }


    // ----- SPECIAL FUNCTIONS -----

    /// @notice Allows this contract to receive Ether
    /// @dev Without this, the contract would reject incoming ETH.
    ///      When the first buyer purchases a ticket from the organizer,
    ///      the payment is sent to the previousOwner (which is this factory).
    ///      This receive() function lets the factory accept those payments.
    ///      Same pattern as in our CondoLeaseContract.
    receive() external payable {}


    // ----- CONSTRUCTOR -----

    /// @dev Sets the deployer as the permanent organizer
    constructor() {
        organizer = msg.sender;
        eventCancelled = false;
    }


    // ----- TICKET CREATION -----

    /// @notice Create a single ticket
    /// @param _eventName Name of the event
    /// @param _price Base price in Wei
    function createTicket(string memory _eventName, uint256 _price) external onlyOrganizer {
        require(!eventCancelled, "Event has been cancelled");

        // Deploy a new Ticket child contract and store its address
        Ticket newTicket = new Ticket(_eventName, _price, address(this));
        allTickets.push(newTicket);
        currentEventName = _eventName;

        emit TicketCreated(address(newTicket), _eventName, _price);
    }

    /// @notice Create multiple tickets in one transaction (batch minting)
    /// @param _eventName Name of the event
    /// @param _price Base price in Wei (same for all tickets in this batch)
    /// @param _count How many tickets to create (1 to 50)
    /// @dev The 50-ticket cap prevents the transaction from running out of gas.
    ///      Each ticket deployment costs ~200k-300k gas, so 50 tickets = ~15M gas,
    ///      which fits within typical block gas limits.
    function createTickets(string memory _eventName, uint256 _price, uint256 _count) external onlyOrganizer {
        require(!eventCancelled, "Event has been cancelled");
        require(_count > 0 && _count <= 50, "Batch size must be 1-50");

        for (uint256 i = 0; i < _count; i++) {
            // Deploy a new Ticket contract and add it to the master list
            Ticket newTicket = new Ticket(_eventName, _price, address(this));
            allTickets.push(newTicket);
            emit TicketCreated(address(newTicket), _eventName, _price);
        }
        currentEventName = _eventName;
    }


    // ----- EVENT MANAGEMENT -----

    /// @notice Cancel the entire event and refund all ticket holders
    /// @dev This function:
    ///      1. Sets eventCancelled to true (blocks future ticket creation)
    ///      2. Loops through every ticket and marks it as Cancelled
    ///      3. Refunds originalPrice to every current ticket holder
    ///      The factory must have enough ETH balance to cover refunds.
    ///      It accumulates ETH from primary sales automatically.
    function cancelEvent() external onlyOrganizer {
        require(!eventCancelled, "Event already cancelled");
        eventCancelled = true;

        uint256 count = allTickets.length;
        for (uint256 i = 0; i < count; i++) {
            Ticket ticket = allTickets[i];
            ticket.cancelTicket();   // Mark the ticket as cancelled
            ticket.refundBuyer();    // Send originalPrice back to the holder
        }

        emit EventCancelled(currentEventName, count);
    }


    // ----- VIEW FUNCTIONS (read-only, no gas cost) -----

    /// @notice Get the full list of all deployed ticket contracts
    function getDeployedTickets() public view returns (Ticket[] memory) {
        return allTickets;
    }

    /// @notice Get the total number of tickets (cheaper than fetching the whole array)
    function getTicketCount() public view returns (uint256) {
        return allTickets.length;
    }
}
