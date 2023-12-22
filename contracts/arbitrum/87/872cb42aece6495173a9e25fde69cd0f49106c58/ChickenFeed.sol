// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./LottoBase.sol";
import "./ISuperdraw.sol";

contract ChickenFeed is LottoBase {
    using SafeERC20 for IERC20;

// STATE VARIABLES

    /// @dev SuperDraw % of prize pool
    uint256 public superDrawPercent;

    /// @dev Price of the ticket
    uint256 public ticketPrice;

    /// @dev Number of tickets required to feed the chicken
    uint256 public numberOfTickets;

    /// @dev This is the Superdraw contract
    ISuperdraw public superdrawContract;

// CONSTRUCTOR

    constructor(
        uint256 _ticketPrice,
        uint256 _numTickets,
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
        paymentContract = IERC20(_paymentAddress);            // Set contract for payments
        superdrawContract = ISuperdraw(_superdrawContract);   // Set the Superdraw Contract
        ticketPrice = _ticketPrice;                           // Set initial ticket price
        numberOfTickets = _numTickets;                        // Set initial number of tickets
        drawTarget = _drawTarget;                             // Set the draw length
        winnerPercent = _winnerPercent;                       // Set initial winners %
        nextDrawPercent = _nextDrawPercent;                   // Set initial next draw %
        burnPercent = _burnPercent;                           // Set initial burn %
        closerFeePercent = _closerFeePercent;                 // Set initial closers fee %
        superDrawPercent = _superDrawPercent;                 // Set initial superdraw %
        Draw memory firstDraw;                                 // Instantiate instance of Draw
        draws.push(firstDraw);                                 // Create the first draw
        draws[0].target = block.number + _drawTarget;         // Start the first draw by setting the deadline
    }

// EVENTS

    event PriceChanged(address updatedBy, uint256 newPrice);
    event TicketsChanged(address updatedBy, uint256 newNumberOfTickets);
    
// MODIFIERS

    /// @dev Only after the current draw has reached it's target is this action allowed
    modifier afterTarget() override {
        require(block.number > draws[getCurrentDraw()].target, "The draw deadline was not reached yet");
        _;
    }

    /// @dev Only before the current draw has reached it's deadline is this action allowed
    modifier withinTarget() override {
        require(block.number <= draws[getCurrentDraw()].target, "This draw has reached its deadline");
        _;
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
    function buyTicket()
        external
        nonReentrant
        whenNotPaused
        withinTarget
    {
        uint256 superDraw = 0;
        uint256 numTickets = numberOfTickets;
        uint256 priceToPay = ticketPrice * numTickets;                                              // Calculate Tokens to Pay
        require( paymentContract.balanceOf(_msgSender()) >= priceToPay,                             "Balance too low to pay for tickets" );
        Draw storage draw = draws[getCurrentDraw()];                                                // Shortcut accessor for the Draw
        draw.winnersAddress = _msgSender();
        draw.numberOfTickets = draw.numberOfTickets + numTickets;                                   // Add the number of tickets sold
        draw.target = getNextTarget();                                                              // Extend the target
        if ( superDrawPercent > 0 ) {
            superDraw = priceToPay * superDrawPercent / 100;                                        // Calculate amount to go to super draw
        }
        draw.prizePool = draw.prizePool + priceToPay - superDraw;                                   // Add to the pize pool (excludes Superdraw)
        emit TicketsAdded(_msgSender(), priceToPay, numTickets);                                                  // Write an event to the chain
        if ( superDraw > 0 ) {
            superdrawContract.addTickets(numTickets, _msgSender(), superDraw);                      // Add to superdraw
            paymentContract.safeTransferFrom(_msgSender(), address(superdrawContract), superDraw);  // Take the tokens for superdraw
        }
        paymentContract.safeTransferFrom(_msgSender(), address(this), priceToPay - superDraw);      // Take the tokens for tickets
    }

    /// @dev EXTERNAL: Closes the current draw, starts the next draw, chooses the winner, 
    /// @dev passes part of the prize pool to the next draw & the super draw, completes the burn & pays the closer
    function closeDraw()
        override
        external
        nonReentrant
        afterTarget
    {
        Draw storage draw = draws[getCurrentDraw()];                                  // Shortcut accessor for the Draw
        require(draw.drawStatus == State.Open,                                         "The lottery has ended. Please check if you won the price!");

        (uint256 winnerPrize, uint256 closersFee, uint256 burnAmount,
        uint256 nextDrawAmount) = splitPrizePool(draw.prizePool);                     // Split the pool and allocate to the various pots

        if (draw.numberOfTickets > 0 ) {
                draw.winnerPrize = winnerPrize;                                       // Update the winners prize
        } else {
            nextDrawAmount = draw.prizePool;                                          // Roll over the prize pool into the next draw
            draw.winnerPrize = 0;                                                     // No winners prize
            closersFee = 0;                                                           // No closers fee forfor a roll over draw
            burnAmount = 0;                                                           // No burn for a roll over draw
        }
        draw.drawStatus = State.Closed;                                               // Flag draw as ended
        emit DrawClosed(_msgSender(), burnAmount, closersFee, nextDrawAmount);                      // Write an event to the chain
        Draw memory nextDraw;                                                         // Instantiate instance of draw
        draws.push(nextDraw);                                                         // Create the next draw
        draws[getCurrentDraw()].target = getNextTarget();                             // Start next draw by setting the target
        draws[getCurrentDraw()].prizePool = nextDrawAmount;                           // Seeds the next draw
        if (closersFee > 0) {
            paymentContract.safeTransfer(_msgSender(), closersFee);                   // Send to the close fee to the caller
        }
        if (burnAmount > 0) {
            IERC777(address(paymentContract)).burn(burnAmount,"");                    // The Burn
        }
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

    /// @dev ADMIN: Owner can set the price
    /// @param numTickets The new number of tickets
    function setNumberOfTickets(uint256 numTickets)
        external
        onlyOwner
    {
        if ( numTickets != 0 && 
             numTickets != numberOfTickets
        ) {
            numberOfTickets = numTickets;
            emit TicketsChanged(_msgSender(), numTickets);
        }
    }

    /// @dev ADMIN: Owner can change the Superdraw address
    /// @param superdrawContractAddress The address of the new Farmland Superdraw contract
    function setSuperDrawContract(address superdrawContractAddress)
        external
        onlyOwner
    {
        superdrawContract = ISuperdraw(superdrawContractAddress);                    // Reset the Superdraw contract
        emit ContractAddressChanged(_msgSender(), "Superdraw Contract", superdrawContractAddress); // Write an event to the chain
    }

    /// @dev ADMIN: Owner can change the draw payout structure
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
