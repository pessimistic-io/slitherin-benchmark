// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./LottoBase.sol";
import "./ISuperdraw.sol";

contract Lotto is LottoBase {
    using SafeERC20 for IERC20;

// STATE VARIABLES

    /// @dev SuperDraw % of prize pool
    uint256 public superDrawPercent;

    /// @dev Price of the ticket
    uint256 public ticketPrice;

    /// @dev This is the Superdraw contract
    ISuperdraw public superdrawContract;

// CONSTRUCTOR

    constructor(
        uint256 _ticketPrice,
        address _paymentAddress,
        address _superdrawContract,
        uint256 _drawTarget,
        uint256 _winnerPercent,
        uint256 _nextDrawPercent,
        uint256 _burnPercent,
        uint256 _closerFeePercent,
        uint256 _superDrawPercent
        
        )
    {
        paymentContract = IERC20(_paymentAddress);                    // Set contract for payments
        superdrawContract = ISuperdraw(_superdrawContract);           // Set Contract for the Superdraw
        ticketPrice = _ticketPrice;                                   // Set initial ticket price
        drawTarget = _drawTarget;                                     // Set the draw length
        winnerPercent = _winnerPercent;                               // Set initial winners %
        nextDrawPercent = _nextDrawPercent;                           // Set initial next draw %
        burnPercent = _burnPercent;                                   // Set initial burn %
        closerFeePercent = _closerFeePercent;                         // Set initial closers fee %
        superDrawPercent = _superDrawPercent;                         // Set initial superdraw %
        Draw memory firstDraw;                                         // Instantiate instance of Draw
        draws.push(firstDraw);                                         // Create the first draw
        draws[0].target = block.number + _drawTarget;                 // Start the first draw by setting the deadline
    }

// EVENTS

    event PriceChanged(address updatedBy, uint256 newPrice);

// MODIFIERS

    /// @dev Only after the current draw has reached it's target is this action allowed
    modifier afterTarget() override {
        require(block.number > draws[getCurrentDraw()].target, "The draw deadline was not reached yet");
        _;
    }

    /// @dev Only before the current draw has reached it's deadline is this action allowed
    modifier withinTarget() override {
        require(block.number <= draws[getCurrentDraw()].target, "This draw has reached its deadline");        _;
    }

    /// @dev Only when the draw is complete is this action allowed
    /// @param drawIndex Which draw are you checking?
    modifier drawComplete(uint256 drawIndex) override {
        require(drawIndex < getCurrentDraw(),                "Draw out of range");
        require(block.number > draws[drawIndex].target,      "This draw is still open");
        require(draws[drawIndex].drawStatus == State.Closed, "This draw still needs to be closed");
        _;
    }

// PUBLIC FUNCTIONS

    /// @dev EXTERNAL: Anyone can buy a ticket
    /// @param numTickets Number of lotto tickets
    function buyTicket(uint256 numTickets)
        external
        nonReentrant
        whenNotPaused
        withinTarget
    {
        uint256 superDraw = 0;
        Draw storage draw = draws[getCurrentDraw()];                                                // Shortcut accessor for the Draw
        require( numTickets < 101,                                                                 "You can buy a maximum of 100 tickets" );
        uint256 priceToPay = ticketPrice * numTickets;                                             // Calculate Tokens to Pay
        require( paymentContract.balanceOf(_msgSender()) >= priceToPay,                             "Balance too low to pay for tickets" );
        draw.numberOfTickets = draw.numberOfTickets + numTickets;                                  // Add the number of tickets sold
        for (uint i = 0; i < numTickets; i++) {                                                    // Loop through the players
            draw.players.push(_msgSender());                                                        // Add players address for each ticket
        }
        emit TicketsAdded(_msgSender(), priceToPay, numTickets);                                                 // Write an event to the chain
        if ( superDrawPercent > 0 ) {
            superDraw = priceToPay * superDrawPercent / 100;                                        // calculate amount to go to super draw
        }
        draw.prizePool = draw.prizePool + priceToPay - superDraw;                                   // Add to the pize pool (excludes Superdraw)
        if ( superDraw > 0 ) {
            superdrawContract.addTickets(numTickets, _msgSender(), superDraw);                     // Add to superdraw
            paymentContract.safeTransferFrom(_msgSender(), address(superdrawContract), superDraw);  // Take the tokens for tickets
        }
        paymentContract.safeTransferFrom(_msgSender(), address(this), priceToPay - superDraw);      // Take the tokens for tickets
    }

// ADMIN FUNCTIONS

    /// @dev ADMIN: Owner can set the price
    /// @param price The new price
    function setPrice(uint256 price)
        external
        onlyOwner
    {
        if ( price != 0 && 
             price != ticketPrice
        ) {
            ticketPrice = price;
            emit PriceChanged(_msgSender(), price);
        }
    }

    /// @dev ADMIN: Owner can change the Superdraw address
    /// @param superdrawContractAddress The address of the new Farmland Superdraw contract
    function setSuperDrawContract(address superdrawContractAddress)
        external
        onlyOwner
    {
        superdrawContract = ISuperdraw(superdrawContractAddress);                       // Reset the Superdraw contract
        emit ContractAddressChanged(_msgSender(), "Superdraw Contract", superdrawContractAddress);    // Write an event to the chain
    }

    /// @dev ADMIN: Owner can change % that goes to the Superdraw
    /// @param superDraw The percentage of the prize pool allocated to super draw
    function setSuperdraw(uint256 superDraw)
        external
        onlyOwner
    {
        superDrawPercent = superDraw;                        // Reset the % that goes to the Superdraw
        emit PayoutStructureChanged(_msgSender(), 0, 0, 0, 0, superDraw);  // Write an event to the chain
    }

// GETTERS

    /// @dev INTERNAL: Get next target
    function getNextTarget()
        override
        view
        internal
        returns (uint256 nextTarget)
    {
        nextTarget = block.number + drawTarget;
    }
}
