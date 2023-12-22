// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./LottoBase.sol";
import "./AddressWhitelist.sol";

contract Superdraw is AddressWhitelist, LottoBase {
   using SafeERC20 for IERC20;

// CONSTRUCTOR

    constructor(
        address _paymentAddress,
        uint256 _drawTarget,
        uint256 _winnerPercent,
        uint256 _nextDrawPercent,
        uint256 _burnPercent,
        uint256 _closerFeePercent
        )
    {
        paymentContract = IERC20(_paymentAddress);           // Set contract for payments
        drawTarget = _drawTarget;                            // Set the draw length
        winnerPercent = _winnerPercent;                      // Set initial winners %
        nextDrawPercent = _nextDrawPercent;                  // Set initial next draw %
        burnPercent = _burnPercent;                          // Set initial burn %
        closerFeePercent = _closerFeePercent;                // Set initial closers fee %
        Draw memory firstDraw;                                // Instantiate instance of Draw
        draws.push(firstDraw);                                // Create the first draw
        draws[0].target = _drawTarget;                       // Start the first draw by setting the target
    }

    /// @dev EXTERNAL: Whitelisted contracts cans enter a ticket
    /// @param numTickets List of tickets to enter
    /// @param entrant The address for the entrant
    /// @param amountAddedToPrizePool Amount added to the prize pool
    function addTickets(uint256 numTickets, address entrant, uint256 amountAddedToPrizePool)
        virtual
        external
        nonReentrant
        whenNotPaused
        onlyWhitelisted
    {
        Draw storage draw = draws[getCurrentDraw()];                          // Shortcut accessor for the Draw
        draw.numberOfTickets = draw.numberOfTickets + numTickets;            // Add the number of tickets sold
        draw.prizePool = draw.prizePool + amountAddedToPrizePool;            // Add the amount to the prize pool
        for (uint i = 0; i < numTickets; i++) {                              // Loop through the number of tickets
            draw.players.push(entrant);                                      // Add address for each ticket to the draw
        }
        emit TicketsAdded(_msgSender(), amountAddedToPrizePool, numTickets);              // Write an event to the chain
    }
}
