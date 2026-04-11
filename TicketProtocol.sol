// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Ticket {

    address public currentOwner;
    address public eventOrganizer;
    string public eventName;
    uint256 public originalPrice;
    uint256 public maxResalePrice;

    enum Status { Available, ForSale, Sold, Cancelled }
    Status public status;

    uint256 public salePrice;

    event TicketListed(address indexed ticketAddress, uint256 salePrice);
    event TicketSold(address indexed ticketAddress, address indexed from, address indexed to, uint256 price);

    modifier onlyOwner() {
        require(msg.sender == currentOwner, "Not the ticket owner");
        _;
    }

    constructor(string memory _eventName, uint256 _originalPrice, address _organizer) {
        eventOrganizer = _organizer;
        currentOwner = _organizer;
        eventName = _eventName;
        originalPrice = _originalPrice;
        maxResalePrice = _originalPrice + (_originalPrice * 10 / 100);
        status = Status.Available;
    }

    function listForSale(uint256 _price) external onlyOwner {
        require(status == Status.Available || status == Status.Sold, "Ticket not listable");
        require(_price <= maxResalePrice, "Price exceeds 110% anti-scalping limit!");

        salePrice = _price;
        status = Status.ForSale;
        emit TicketListed(address(this), _price);
    }

    function unlistForSale() external onlyOwner {
        require(status == Status.ForSale, "Ticket is not listed for sale");
        status = Status.Sold;
        salePrice = 0;
    }

    function buyTicket() external payable {
        require(status == Status.ForSale, "Ticket is not currently for sale");
        require(msg.value == salePrice, "Incorrect payment amount");

        address previousOwner = currentOwner;

        currentOwner = msg.sender;
        status = Status.Sold;

        (bool sent, ) = payable(previousOwner).call{value: msg.value}("");
        require(sent, "Payment transfer failed");

        emit TicketSold(address(this), previousOwner, msg.sender, msg.value);
    }

    function transferTicket(address _newOwner) external onlyOwner {
        require(status != Status.Cancelled, "Cannot transfer a cancelled ticket");
        require(status != Status.ForSale, "Unlist the ticket before transferring");
        require(_newOwner != address(0), "Cannot transfer to zero address");
        require(_newOwner != msg.sender, "Cannot transfer to yourself");

        address previousOwner = currentOwner;
        currentOwner = _newOwner;

        emit TicketSold(address(this), previousOwner, _newOwner, 0);
    }

    function cancelTicket() external {
        require(msg.sender == eventOrganizer, "Only organizer can cancel");
        require(status != Status.Cancelled, "Already cancelled");
        status = Status.Cancelled;
    }

    function refundBuyer() external {
        require(msg.sender == eventOrganizer, "Only organizer can refund");
        require(status == Status.Cancelled, "Ticket must be cancelled first");

        if (currentOwner == eventOrganizer) {
            return;
        }

        address payable refundRecipient = payable(currentOwner);
        uint256 refundAmount = originalPrice;

        currentOwner = eventOrganizer;

        (bool sent, ) = refundRecipient.call{value: refundAmount}("");
        require(sent, "Refund transfer failed");

        emit TicketSold(address(this), refundRecipient, eventOrganizer, refundAmount);
    }
}

contract EventOrganizer {

    Ticket[] public allTickets;
    address public organizer;
    string public currentEventName;
    bool public eventCancelled;

    event TicketCreated(address indexed ticketAddress, string eventName, uint256 originalPrice);
    event EventCancelled(string eventName, uint256 ticketCount);

    modifier onlyOrganizer() {
        require(msg.sender == organizer, "Only organizer can do this");
        _;
    }

    receive() external payable {}

    constructor() {
        organizer = msg.sender;
        eventCancelled = false;
    }

    function createTicket(string memory _eventName, uint256 _price) external onlyOrganizer {
        require(!eventCancelled, "Event has been cancelled");

        Ticket newTicket = new Ticket(_eventName, _price, address(this));
        allTickets.push(newTicket);
        currentEventName = _eventName;

        emit TicketCreated(address(newTicket), _eventName, _price);
    }

    function createTickets(string memory _eventName, uint256 _price, uint256 _count) external onlyOrganizer {
        require(!eventCancelled, "Event has been cancelled");
        require(_count > 0 && _count <= 50, "Batch size must be 1-50");

        for (uint256 i = 0; i < _count; i++) {
            Ticket newTicket = new Ticket(_eventName, _price, address(this));
            allTickets.push(newTicket);
            emit TicketCreated(address(newTicket), _eventName, _price);
        }
        currentEventName = _eventName;
    }

    function cancelEvent() external onlyOrganizer {
        require(!eventCancelled, "Event already cancelled");
        eventCancelled = true;

        uint256 count = allTickets.length;
        for (uint256 i = 0; i < count; i++) {
            Ticket ticket = allTickets[i];
            ticket.cancelTicket();
            ticket.refundBuyer();
        }

        emit EventCancelled(currentEventName, count);
    }

    function getDeployedTickets() public view returns (Ticket[] memory) {
        return allTickets;
    }

    function getTicketCount() public view returns (uint256) {
        return allTickets.length;
    }
}
