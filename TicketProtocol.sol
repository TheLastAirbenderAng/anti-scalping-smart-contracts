// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20; // Using the version from your practice slides

/// @title Individual Event Ticket Contract
contract Ticket {
    address public currentOwner;
    address public eventOrganizer;
    string public eventName;
    uint256 public originalPrice;
    uint256 public maxResalePrice;

    bool public isForSale;
    uint256 public salePrice;

    // Restricts actions to the current ticket holder, similar to Heirloom.sol
    modifier onlyOwner() {
        require(msg.sender == currentOwner, "Not the ticket owner");
        _;
    }

    // Constructor sets up the initial ticket rules
    constructor(string memory _eventName, uint256 _originalPrice, address _organizer) {
        eventOrganizer = _organizer;
        currentOwner = _organizer; // Organizer owns it first
        eventName = _eventName;
        originalPrice = _originalPrice;
        
        // Anti-Scalping Math: 110% of the original price
        maxResalePrice = _originalPrice + (_originalPrice * 10 / 100);
        isForSale = false;
    }

    // Step 1: Owner lists the ticket for sale
    function listForSale(uint256 _price) external onlyOwner {
        // This is the core Anti-Scalping feature
        require(_price <= maxResalePrice, "Price exceeds 110% anti-scalping limit!");
        salePrice = _price;
        isForSale = true;
    }

    // Step 2: A buyer purchases the ticket
    function buyTicket() external payable {
        require(isForSale, "Ticket is not currently for sale");
        require(msg.value == salePrice, "Incorrect payment amount");

        address previousOwner = currentOwner;

        // Transfer ownership
        currentOwner = msg.sender;
        isForSale = false; // Take it off the market

        // Forward the payment to the previous owner using the secure call method 
        (bool sent, ) = payable(previousOwner).call{value: msg.value}("");
        require(sent, "Payment transfer failed");
    }
}

/// @title Factory Contract to Generate Tickets
contract EventOrganizer {
    Ticket[] public allTickets;
    address public organizer;

    modifier onlyOrganizer() {
        require(msg.sender == organizer, "Only organizer can do this");
        _;
    }

    constructor() {
        organizer = msg.sender;
    }

    // The organizer deploys a new child contract for every new ticket
    function createTicket(string memory _eventName, uint256 _price) external onlyOrganizer {
        Ticket newTicket = new Ticket(_eventName, _price, address(this));
        allTickets.push(newTicket);
    }

    // View function to retrieve all generated tickets
    function getDeployedTickets() public view returns (Ticket[] memory) {
        return allTickets;
    }
}