// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/*
 * Y   Y   OOO   III  N   N  K   K   !!
 *  Y Y   O   O   I   NN  N  K  K    !! 
 *   Y    O   O   I   N N N  KKK     !! 
 *   Y    O   O   I   N  NN  K  K       
 *   Y     OOO   III  N   N  K   K   !! 
 */

/*
 * @title Yoink!
 * @dev This smart contract facilitates an on-chain PvP (Player versus Player) game called "Yoink". 
 * In this competitive environment, players strive to be the last Yoinker before the timer concludes. 
 * The game operates in perpetual rounds, where each Yoink action post-timer initiates a new round.
 * Players vie for rewards in ETH, which are distributed automatically with the commencement of a new round.
 * The contract handles the game logic, player interactions, and reward distributions.
 *
 * @disclaimer: this game is highly experimental, play at your own cost.
 *
 * Telegram: https://t.me/yoink_official
 * Website/app: https://yoinkit.xyz
 * Twitter: https://twitter.com/Yoink_Game
 */

import "./IERC20.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";

contract Yoink is ReentrancyGuard, Ownable {
    IERC20 public paymentToken;

    address public lastYoinker;
    RoundWinner[] public roundWinners;

    // Totals
    uint256 public totalYoinks;
    uint256 public totalTokensUsed;
    uint256 public totalRewardsWon;

    uint256 public lastYoinkTime;
    uint256 public currentRoundPrizePool;
    uint256 public nextRoundPrizePool;
    uint256 public yoinkCost;
    uint256 public nextRoundYoinkCost;
    uint256 public gameDuration = 120 seconds; // 2 minutes per round initially, will be adjusted throughout if community wants
    uint256 public nextRoundGameDuration;

    mapping(address => uint256) public yoinkCount;
    mapping(address => bool) public isBlacklisted;

    // State
    bool public isActive;

    event Yoinked(address indexed yoinker, uint256 time);
    event PrizeClaimed(address indexed winner, uint256 prizeAmount);
    event RewardsAdded(uint256 amount, address indexed depositor);
    event StuckTokensClaimed(uint256 amount, address indexed owner);
    event GameStarted();
    event GameEnded(address indexed winner, uint256 prizeAmount);

    struct RoundWinner {
        address winner;
        uint256 reward;
    }

    constructor(uint256 _yoinkCost) {
        yoinkCost = _yoinkCost;
        isActive = false;
    }

    modifier gameActive() {
        require(isActive, "Game is not active");
        _;
    }

    modifier notBlacklisted() {
        require(!isBlacklisted[msg.sender], "Address blacklisted");
        _;
    }

    // function to accept ether and update prize pools accordingly
    receive() external payable {
        if (isActive && (lastYoinkTime + gameDuration > block.timestamp)) {
            currentRoundPrizePool += msg.value; // Add to the current round if the game is active
        } else {
            nextRoundPrizePool += msg.value; // Otherwise, add to the next round
        }
        emit RewardsAdded(msg.value, msg.sender);
    }

    /* VIEW */
    // Returns the current prize pool
    function getCurrentPrizePool() external view returns (uint256) {
        return currentRoundPrizePool;
    }

    // Returns the time left for the game to end
    function timeUntilEnd() external view returns (uint256) {
        if (lastYoinkTime == 0) {
            return gameDuration;
        }
        uint256 timeElapsed = block.timestamp - lastYoinkTime;
        return timeElapsed >= gameDuration ? 0 : gameDuration - timeElapsed;
    }

    /* INTERNAL */
    // Internal function to check and update the game status based on the time and active flag
    function _checkGameStatus() internal {
        if (
            lastYoinkTime != 0 &&
            block.timestamp > lastYoinkTime + gameDuration &&
            isActive
        ) {
            uint256 prizeAmount = currentRoundPrizePool; // Use the segregated prize pool
            payable(lastYoinker).transfer(prizeAmount);
            totalRewardsWon += prizeAmount; // Increment the total rewards sent

            emit PrizeClaimed(lastYoinker, prizeAmount);
            emit GameEnded(lastYoinker, prizeAmount);

            // Store the winner of this round and their reward
            roundWinners.push(
                RoundWinner({winner: lastYoinker, reward: prizeAmount})
            );

            // Transfer next round's pool to the current round and reset next round's pool
            currentRoundPrizePool = nextRoundPrizePool;
            nextRoundPrizePool = 0;

            // Update yoinkCost for the next round
            if (nextRoundYoinkCost > 0) {
                yoinkCost = nextRoundYoinkCost;
                nextRoundYoinkCost = 0; // Reset nextRoundYoinkCost
            }

            // Update gameDuration for the next round if nextRoundGameDuration has been set
            if (nextRoundGameDuration > 0) {
                gameDuration = nextRoundGameDuration;
                nextRoundGameDuration = 0; // Reset nextRoundGameDuration
            }

            // Reset game state for the next round
            lastYoinker = address(0);
            lastYoinkTime = 0;
            isActive = true;
        }
    }

    // Handles the transfer and burn of tokens for a Yoink
    function _handleTokenTransferAndBurn() internal {
        require(
            paymentToken.transferFrom(msg.sender, address(this), yoinkCost),
            "Transfer of tokens to contract failed"
        );

        require(
            paymentToken.transfer(
                0x000000000000000000000000000000000000dEaD,
                yoinkCost
            ),
            "Transfer of tokens to dead address failed"
        );
    }

    // Validates the conditions for a Yoink
    function _validateYoinkConditions() internal view {
        require(isActive, "The game is not active");
        require(msg.sender == tx.origin, "Sender cannot be a contract");
        uint256 balance = paymentToken.balanceOf(msg.sender);
        require(balance >= yoinkCost, "Not enough $TOKEN tokens");
        uint256 allowance = paymentToken.allowance(msg.sender, address(this));
        require(
            allowance >= yoinkCost,
            "Contract not approved to spend enough $TOKEN tokens"
        );
    }

    // Updates the game state post a Yoink
    function _updateGameState() internal {
        lastYoinker = msg.sender;
        lastYoinkTime = block.timestamp;
        yoinkCount[msg.sender]++;
        totalYoinks++;
        totalTokensUsed += yoinkCost;
        emit Yoinked(msg.sender, block.timestamp);
    }

    /* EXTERNAL */
    // Sets the payment token for the game
    function setPaymentToken(address _paymentToken) external onlyOwner {
        require(
            address(paymentToken) == address(0),
            "PaymentToken is already set"
        );
        paymentToken = IERC20(_paymentToken);
    }

    // Allows the owner to add funds to the prize pool
    function addFundsToPrizePool() external payable onlyOwner {
        require(msg.value > 0, "Amount should be greater than 0");
        if (isActive && (lastYoinkTime + gameDuration > block.timestamp)) {
            currentRoundPrizePool += msg.value; // Add to the current round if the game is active
        } else {
            nextRoundPrizePool += msg.value; // Otherwise, add to the next round
        }
        emit RewardsAdded(msg.value, msg.sender);
    }

    // Set the cost to yoink, takes effect on the next round
    function setYoinkCost(uint256 _yoinkCost) external onlyOwner {
        nextRoundYoinkCost = _yoinkCost;
    }

    // Set the new game duration in seconds, takes effect on the next round
    function setNextRoundGameDuration(uint256 _gameDuration)
        external
        onlyOwner
    {
        nextRoundGameDuration = _gameDuration;
    }

    // Main function for players to perform a Yoink
    function yoinkIt() external nonReentrant gameActive notBlacklisted {
        _checkGameStatus();
        _validateYoinkConditions();
        _handleTokenTransferAndBurn();
        _updateGameState();
    }

    // Starts the game (should only be called once before the first round)
    function startGame() external onlyOwner {
        require(
            address(paymentToken) != address(0),
            "PaymentToken must be set before starting the game"
        );
        require(!isActive, "Game is already active");
        isActive = true;

        // Transfer nextRoundPrizePool to currentRoundPrizePool at the start of the game
        currentRoundPrizePool += nextRoundPrizePool;
        nextRoundPrizePool = 0;

        emit GameStarted();
    }

    // Stops the game (only use if needed!)
    function stopGame() external onlyOwner {
        require(isActive, "Game is already inactive");
        isActive = false;
    }

    // Function to blacklist an address
    function blacklistBot(address _address) external onlyOwner {
        require(_address != address(0), "Invalid address");
        isBlacklisted[_address] = true;
    }

    // Function to remove an address from the blacklist
    function unblacklistBot(address _address) external onlyOwner {
        require(_address != address(0), "Invalid address");
        isBlacklisted[_address] = false;
    }

    // Allows the owner to withdraw all Ether (only use if needed!)
    function emergencyWithdrawETH() external onlyOwner {
        uint256 balance = address(this).balance;
        payable(owner()).transfer(balance);
    }

    // Allows the owner to claim the remaining tokens (only use if needed!)
    function emergencyWithdrawTokens() external onlyOwner {
        uint256 balance = paymentToken.balanceOf(address(this));
        require(
            paymentToken.transfer(owner(), balance),
            "Transfer of tokens to owner failed"
        );
        emit StuckTokensClaimed(balance, owner());
    }
}
