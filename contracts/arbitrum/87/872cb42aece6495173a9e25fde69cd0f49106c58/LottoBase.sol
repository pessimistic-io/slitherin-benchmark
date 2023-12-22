// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SafeERC20.sol";
import "./Ownable.sol";
import "./interfaces_IERC20.sol";
import "./interfaces_IERC777.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";

import "./IRandomNumbers.sol";

enum State {Open, Closed, Pending}
struct Draw { address winnersAddress; bool prizeClaimed; address[] players; uint256 prizePool; State drawStatus; uint256 target; uint256 winnerPrize; uint256 numberOfTickets;}

abstract contract LottoBase is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

// STATE VARIABLES

    /**
     * @dev PUBLIC: Stores all the draws
     */
    Draw[] public draws;
    
    /// @dev Winners % of prize pool
    uint256 public winnerPercent;

    /// @dev Next Draw % of prize pool
    uint256 public nextDrawPercent;

    /// @dev Burn % of prize pool
    uint256 public burnPercent;

    /// @dev Closers % of prize pool
    uint256 public closerFeePercent;

    /// @dev Target for each draw
    uint256 public drawTarget;

    /// @dev This is the contract used to pay for tickets
    IERC20 public paymentContract;

    /// @dev Initialise the nonce used to generate pseudo random numbers
    uint256 private randomNonce;

    /// @dev This is the external VRF contract to generate random numbers
    IRandomNumbers public randomContract;

// EVENTS

    event ContractAddressChanged(address updatedBy, string addressType, address newAddress);
    event TicketsAdded(address updatedBy, uint256 pricePaid, uint256 totalTickets);
    event DrawClosed(address updatedBy, uint256 burnedAmount, uint256 closerFee, uint256 nextDrawAmount);
    event PrizeClaimed(address updatedBy, uint256 amountClaimed);
    event PayoutStructureChanged(address updatedBy, uint256 winnerPercent, uint256 burnPercent, uint256 closerFeePercent, uint256 nextDrawPercent, uint256 superDrawPercent);
    event DrawTargetChanged(address updatedBy, uint256 newTarget);

// MODIFIERS

    /// @dev Only after the current draw has reached it's target is this action allowed
    modifier afterTarget() virtual {
        require(draws[getCurrentDraw()].prizePool > draws[getCurrentDraw()].target, "The draw target was not reached yet");
        _;
    }

    /// @dev Only before the current draw has reached it's target is this action allowed
    modifier withinTarget() virtual {
        require(draws[getCurrentDraw()].prizePool <= draws[getCurrentDraw()].target, "This draw has reached its target");
        _;
    }

    /// @dev Only when the draw is complete is this action allowed
    /// @param drawIndex Which draw are you checking?
    modifier drawComplete(uint256 drawIndex) virtual {
        require(drawIndex < getCurrentDraw(),                          "Draw out of range");
        require(draws[drawIndex].prizePool > draws[drawIndex].target, "This draw is still open");
        require(draws[drawIndex].drawStatus == State.Closed,           "This draw still needs to be closed");
        _;
    }

    /// @dev Only allows winners to perform this action
    /// @param drawIndex Which draw are you checking?
    modifier isWinner(uint256 drawIndex) virtual {
        require(drawIndex < getCurrentDraw(),                    "Draw out of range");
        require(draws[drawIndex].prizePool > 0,                  "No prize for this draw");
        require(!draws[drawIndex].prizeClaimed,                  "Prize already claimed");
        require(_msgSender() == draws[drawIndex].winnersAddress, "Sorry, you did not win this time!");
        _;
    }

    /// @dev Only allows existing draws
    /// @param drawIndex Which draw are you checking?
    modifier isADraw(uint256 drawIndex) virtual {
        require(drawIndex < getCurrentDraw(), "Draw out of range");
        _;
    }

    /// @dev Only allow VRF random contract to perform this action
    modifier isVRFContract() virtual {
        require(_msgSender() <= address(randomContract), "Only permitted by VRF Contract");
        _;
    }

// PUBLIC FUNCTIONS

    /// @dev EXTERNAL: Winner can claim a prize
    /// @param drawIndex Which draw are you claiming for?
    function claimWinningPrize(uint256 drawIndex)
        virtual
        external
        nonReentrant
        drawComplete(drawIndex)
        isWinner(drawIndex)
    {
        Draw storage draw = draws[drawIndex];                          // Shortcut accessor for the Draw
        uint256 amount = draw.winnerPrize;                              // Calculate the prize for this Draw
        require (paymentContract.balanceOf(address(this)) >= amount,    "Contract balance isnt enough to cover the winner");
        draw.prizeClaimed = true;                                       // Set prize as claimed
        emit PrizeClaimed(_msgSender(), amount);                                      // Write an event to the chain
        paymentContract.safeTransfer(_msgSender(), amount);             // Pay winner
    }

    /// @dev EXTERNAL: Closes the current draw, starts the next draw, chooses the winner, 
    /// @dev passes part of the prize pool to the next draw & the super draw, completes the burn & pays the closer
    function closeDraw()
        virtual
        external
        nonReentrant
        afterTarget
    {
        Draw storage draw = draws[getCurrentDraw()];                                  // Shortcut accessor for the Draw
        require(draw.drawStatus == State.Open,                                        "The lottery has ended. Please check if you won the price!");
        
        (uint256 winnerPrize, uint256 closersFee, uint256 burnAmount,
        uint256 nextDrawAmount) = splitPrizePool(draw.prizePool);                     // Split the pool and allocate to the various pots

        uint256 randomNumber = 0;                                                     // Instantiate the random number used to choose the winner
        uint256 numberOfPlayers = draw.players.length;                                // Store the number of players in a local variable saves gas
        bool isVRFActive = isVRF();                                                   // Store if the VRF contract has been activated
        if (numberOfPlayers > 0 ) {
            if (!isVRFActive) {
                randomNumber = getRandomNumber();                                     // Retrieve random number from internal function
                draw.winnersAddress = draw.players[randomNumber % numberOfPlayers];   // Assign winner using internal randomness
                draw.drawStatus = State.Closed;                                       // Flag draw as ended
            } else {
                randomContract.getRandomNumber(getCurrentDraw());                     // Request random number
                draw.drawStatus = State.Pending;
            }
            draw.winnerPrize = winnerPrize;                                           // Update the winners prize
        } else {
            nextDrawAmount = draw.prizePool;                                          // Roll over the prize pool into the next draw
            draw.winnerPrize = 0;                                                     // No winners prize
            closersFee = 0;                                                           // No closers fee forfor a roll over draw
            burnAmount = 0;                                                           // No burn for a roll over draw
            draw.drawStatus = State.Closed;                                           // Flag draw as ended
        }
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

    /// @dev EXTERNAL: Call back function for the VRF co-ordinator to choose winner & close the draw
    /// @param drawIndex Which draw are you closing?
    /// @param randomNumber This is the random number to choose a winner
    function chooseWinnerVRF(uint256 drawIndex, uint256 randomNumber)
        virtual
        external
        isADraw(drawIndex)
        isVRFContract
    {
        Draw storage draw = draws[drawIndex];                                        // Shortcut accessor for the Draw
        require(draw.drawStatus == State.Pending,                                     "This draw is needs to be pending");
        uint256 numberOfPlayers = draw.players.length;                                // Store the number of players in a local variable saves gas
        draw.winnersAddress = draw.players[randomNumber % numberOfPlayers];          // Assign winner using external randomness
        draw.drawStatus = State.Closed;                                               // Flag draw as ended
    }

// INTERNAL FUNCTIONS

    /// @dev INTERNAL: Generates a random number to choose a winner
    function getRandomNumber()
        virtual
        internal
        returns (uint256 randomNumber)
    {
        randomNonce++;
        return uint256(keccak256(abi.encodePacked(block.timestamp, _msgSender(), randomNonce)));
    }

// ADMIN FUNCTIONS

    /// @dev ADMIN: Owner can set the draw target
    /// @param newDrawtarget The new draw target
    function setDrawTarget(uint256 newDrawtarget)
        virtual
        external
        onlyOwner
    {
        if ( newDrawtarget != 0 && 
             newDrawtarget != drawTarget
        ) {
            drawTarget = newDrawtarget;
            emit DrawTargetChanged(_msgSender(), newDrawtarget);
        }
    }

    /// @dev ADMIN: Owner can start or pause the contract
    /// @param value False starts & True pauses the contract
    function isPaused(bool value)
        virtual
        external
        onlyOwner 
    {
        if ( !value ) {
            _unpause();
        } else {
            _pause();
        }
    }

    /// @dev ADMIN: Owner can change the draw payout structure
    /// @param winner The percentage of the prize pool allocated to the winner
    /// @param burn The percentage of the prize pool allocated to the burn
    /// @param closerFee The percentage of the prize pool allocated to the closer
    /// @param nextDraw The percentage of the prize pool allocated to the next draw
    function setPayoutStructure(uint256 winner, uint256 burn, uint256 closerFee, uint256 nextDraw)
        virtual
        external
        onlyOwner
    {
        require ( winner + burn + closerFee + nextDraw == 100, "Total should equal 100");
        winnerPercent = winner;
        burnPercent = burn;
        closerFeePercent = closerFee;
        nextDrawPercent = nextDraw;
        emit PayoutStructureChanged(_msgSender(), winner, burn, closerFee, nextDraw, 0);
    }

    /// @dev ADMIN: Owner can change the payment contract
    /// @param paymentContractAddress The address of the new payment token
    function setPaymentContract(address paymentContractAddress)
        virtual
        external
        onlyOwner
    {
        paymentContract = IERC20(paymentContractAddress);
        emit ContractAddressChanged(_msgSender(), "Payment Contract", paymentContractAddress);
    }

    /// @dev ADMIN: Owner can change the contract that generates the random number
    /// @param randomContractAddress The address of the new randomness contract
    function setRandomnessAddress(address randomContractAddress)
        virtual
        external
        onlyOwner
    {
        randomContract = IRandomNumbers(randomContractAddress);
        emit ContractAddressChanged(_msgSender(), "Random Contract", randomContractAddress);
    }

// GETTERS

    /// @dev INTERNAL: Calculates the split of the prizepool
    function splitPrizePool(uint256 prizePool)
        virtual
        public
        view
        returns (
            uint256 winnersPrize,
            uint256 closersFee,
            uint256 burnAmount,
            uint256 nextDrawAmount
        )
    {
        if ( winnerPercent > 0 ) {
            winnersPrize = prizePool * winnerPercent / 100;             // Calculate winners prize
        }
        if ( closerFeePercent > 0 ) {
            closersFee = prizePool * closerFeePercent / 100;            // Calculate closer fee
        }
        if ( burnPercent > 0 ) {
            burnAmount = prizePool * burnPercent / 100;                 // Calculate burn amount
        }
        if ( nextDrawPercent > 0 ) {
            nextDrawAmount = prizePool * nextDrawPercent / 100;         // Calculate amount to go to next draw
        }
    }

    /// @dev INTERNAL: Get next target
    function getNextTarget()
        virtual
        internal
        view
        returns (uint256 nextTarget)
    {
        nextTarget = drawTarget;
    }

    /// @dev EXTERNAL: Return list of players for a draw
    /// @param drawIndex Which draw?
    function getPlayersByDraw(uint256 drawIndex)
        virtual
        external
        view
        returns (
            address[] memory players                           // Define the array of addresses / players to be returned.
        )
    {
        if ( drawIndex > getCurrentDraw() ) {return players;} // Return empty array if draw out of range
        return draws[drawIndex].players;                       // Return the array of players in a draw
    }

    /// @dev PUBLIC: Returns true if using the VRF randomness contract
    function isVRF()
        virtual
        public
        view
        returns (
            bool
        )
    {
        if (address(randomContract) == address(0)) {
            return false;
            } else {
                return true;
        }
    }

    /// @dev EXTERNAL: Return number of tickets per players for a draw
    /// @param drawIndex Which draw?
    /// @param account Which address?
    function getNumberOfTicketPerAddressByDraw(uint256 drawIndex, address account)
        virtual
        external
        view
        returns (
            uint256 tickets                                                             // Define the return variable
        )
    {
        if ( drawIndex > getCurrentDraw() ) {return 0;}                                 // Return 0 if draw out of range
        uint256 totalTickets = draws[drawIndex].players.length;                         // Store the total number tickets in a local variable
        for(uint256 ticketIndex = 0; ticketIndex < totalTickets; ticketIndex++){         // Loop through the draws
            if ( account == draws[drawIndex].players[ticketIndex] )
                {
                    tickets++;                                                          // Add drawIndex to _winners array
                }
        }
    }

    /// @dev PUBLIC: Return winners address by draw
    /// @param drawIndex Which draw?
    function getWinnerByDraw(uint256 drawIndex)
        virtual
        public
        view
        returns (
            address winner
        )
    {
        if ( drawIndex > getCurrentDraw() ) {
            return address(0);                                 // Return empty array if draw out of range
        }                                                      
        if ( draws[drawIndex].drawStatus != State.Closed )    // Or not closed
        {
            return address(0);                                 // Return zero address 
        }
        return draws[drawIndex].winnersAddress;               // Return the winners address
    }
    
    /// @dev EXTERNAL: Return unclaimed wins by address
    /// @param account Which address?
    function getUnclaimedWinnerByAddress(address account)
        virtual
        external
        view
        returns (uint256[] memory winners)
    {
        uint256 total = getCurrentDraw();                                  // Store the total draws in a local variable
        uint256 unclaimedTotal = 0;                                        
        for(uint256 drawIndex = 0; drawIndex < total; drawIndex++){        // Loop through the draws
            if ( !draws[drawIndex].prizeClaimed &&                         // Check if win is unclaimed
                 draws[drawIndex].numberOfTickets > 0 &&                   // with entrants
                 account == getWinnerByDraw(drawIndex) )
                {
                    unclaimedTotal++;                                      // increment unclaimedTotal
                }
        }
        uint256 winnersIndex = 0;
        uint256[] memory _winners = new uint256[](unclaimedTotal);
        if ( total == 0 ) {
            return new uint256[](0);                                       // Return an empty array
        } else {
            for(uint256 drawIndex = 0; drawIndex < total; drawIndex++){    // Loop through the draws
                if ( !draws[drawIndex].prizeClaimed &&                     // Check if win is unclaimed
                     draws[drawIndex].numberOfTickets > 0 &&               // with entrants
                     account == getWinnerByDraw(drawIndex) )
                     {
                        _winners[winnersIndex] = drawIndex;                // Add drawIndex to _winners array
                        winnersIndex++;
                    }
            }
        }
        return _winners;
    }

    /// @dev PUBLIC: Return current active draw
    function getCurrentDraw()
        virtual
        public
        view
        returns (
            uint256 currentDraw        // Define the return value
        )
    {
        return draws.length - 1;       // Return the length of the draws array
    }
}
