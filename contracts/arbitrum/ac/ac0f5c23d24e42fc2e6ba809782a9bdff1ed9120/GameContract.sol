// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title GameContract
 * @dev A contract for a game that allows players to place bets on odd or even numbers.
 */
interface FoxAIToken {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract GameContract {
    address private owner; // Address of the contract owner
    address private admin; // Address of the contract admin
    address private foxAITokenAddress = 0x516343beAcD9DDCaD23f7101F38d7d0a7F01fd65; // Address of the FoxAIToken contract
    FoxAIToken private foxAIToken; // Instance of the FoxAIToken contract

    struct PlayerInfo {
        address addr; // Address of the player
        uint256 amount; // Bet amount
        bool odd; // Flag indicating if the bet is on an odd number
    }
    PlayerInfo[] private players; // Array to store player information
    uint256 public gameLotteryTime; // Timestamp of the next lottery time

    event BetPlaced(address indexed player, uint256 amount, bool isOdd, uint256 time, uint256 number); // Event emitted when a bet is placed
    event WinnerInfo(address indexed player, uint256 amount, bool isOdd, uint256 time, uint256 number); // Event emitted when a player wins
    event LoserInfo(address indexed player, uint256 amount, bool isOdd, uint256 time, uint256 number); // Event emitted when a player loses    

    /**
     * @dev Modifier to restrict access to the contract owner.
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can perform this action");
        _;
    }

    /**
     * @dev Modifier to restrict access to the contract admin.
     */
    modifier onlyAdmin() {
        require(msg.sender == admin || msg.sender == owner, "Only admin can perform this action");
        _;
    }

    /**
     * @dev Constructor function.
     */
    constructor() {
        owner = msg.sender;
        admin = msg.sender;
        foxAIToken = FoxAIToken(foxAITokenAddress);
    }

    /**
     * @dev Changes the admin address.
     * @param newAdmin The new admin address.
     */
    function changeAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "Invalid admin address");
        admin = newAdmin;
    }

    bool public gameStatus = false; // Flag indicating if the game is active or not

    /**
     * @dev Sets the game status.
     * @param status The game status (true for active, false for inactive).
     */
    function setGameStatus(bool status) external onlyAdmin {
        gameStatus = status;
    }

    uint256 public MAX_PLAYERS = 5; // Maximum number of players allowed in a game

    /**
     * @dev Sets the maximum number of players allowed in a game.
     * @param number The maximum number of players.
     */
    function setGamePlayers(uint256 number) external onlyAdmin {
        require(number > 0, "Number of players must be greater than 0");
        MAX_PLAYERS = number;
    }

    uint256 public GAME_DURATION = 180; // Duration of the game in seconds

    /**
     * @dev Sets the duration of the game.
     * @param ticker The duration of the game in seconds.
     */
    function setGameDuration(uint256 ticker) external onlyAdmin {
        require(ticker > 0, "Duration ticker must be greater than 0");
        GAME_DURATION = ticker;
    }

    uint256 public MAX_BET_BALANCE = 3; // Maximum bet amount as a percentage of the contract balance

    /**
     * @dev Sets the maximum bet amount as a percentage of the contract balance.
     * @param rate The bet balance rate (between 1 and 100).
     */
    function setGameBetBalance(uint256 rate) external onlyAdmin {
        require(rate > 0 && rate <= 100, "Bet balance rate must be between 1 and 100");
        MAX_BET_BALANCE = rate;
    }

    uint256 public prizeRatio = 100; // Ratio of the prize amount to the bet amount

    /**
     * @dev Sets the ratio of the prize amount to the bet amount.
     * @param ratio The ratio (between 1 and 1000).
     */
    function setGameRatio(uint256 ratio) external onlyAdmin {
        require(ratio > 0 && ratio <= 1000, "Ratio must be between 1 and 1000");
        prizeRatio = ratio;
    }

    uint256 public taxRate = 7; // Tax rate as a percentage

    /**
     * @dev Sets the tax rate applied to the prize amount.
     * @param rate The tax rate (between 0 and 100).
     */
    function setTaxRate(uint256 rate) external onlyAdmin {
        require(rate >= 0 && rate <= 100, "Tax rate must be between 0 and 100");
        taxRate = rate;
    }

    /**
     * @dev Returns the current balance of the contract.
     * @return The contract balance.
     */
    function getGameBalance() public view returns (uint256) {
        return foxAIToken.balanceOf(address(this));
    }

    /**
     * @dev Allows a player to place a bet.
     * @param amount The bet amount.
     * @param isOdd Flag indicating if the bet is on an odd number.
     */
    function placeBet(uint256 amount, bool isOdd) external {
        require(gameStatus, "Game is not available");
        require(tx.origin == msg.sender, "Only the game player is allowed to use this contract");
        require(amount > 0, "Amount must be greater than 0");
        require(players.length < MAX_PLAYERS, "Maximum number of players reached");
        require(amount <= getGameBalance() * MAX_BET_BALANCE / 100, "Amount exceeds maximum bet percentage");

        require(foxAIToken.transferFrom(msg.sender, address(this), amount), "Token transfer failed");

        players.push(PlayerInfo(msg.sender, amount, isOdd));

        if (players.length == 1) {
            gameLotteryTime = block.timestamp + GAME_DURATION;
        }

        emit BetPlaced(msg.sender, amount, isOdd, block.timestamp, gameNumber);
        gameCounter++;

        if (players.length == MAX_PLAYERS || block.timestamp >= gameLotteryTime) {
            endGame();
        }
    }

    uint256 private gameCounter = 0;
    uint256 private gameNumber = 1; // Number of winning periods in the game

    /**
     * @dev Ends the game and determines the winners.
     */
    function endGame() private {
        salt = generateRandomNumber() % 100000000;
        uint256 winningSide = generateRandomNumber() % 2;
        
        for (uint256 i = 0; i < players.length; i++) {
            if (players[i].odd == (winningSide == 1)) {

                uint256 winningAmount = players[i].amount * (prizeRatio / 100); // Prize amount is (ratio * bat amout) times the bet amount                
                require(foxAIToken.balanceOf(address(this)) >= (winningAmount + players[i].amount), "Insufficient contract balance for prize payout");

                uint256 taxAmount = 0;
                if (taxRate > 0) {
                    taxAmount = winningAmount * taxRate / 100;
                    uint256 taxPool = taxAmount * 2 / 5; // 40% goes back to the fund pool
                    uint256 taxTeam = taxAmount - taxPool;  // 60% 30% goes to team 1 and to team 2
                    foxAIToken.transfer(_walletTrx, taxTeam);
                }

                uint256 prizeAmount = winningAmount - taxAmount + players[i].amount;
                foxAIToken.transfer(players[i].addr, prizeAmount);

                emit WinnerInfo(players[i].addr, prizeAmount, players[i].odd, block.timestamp, gameNumber);
            } else {
                emit LoserInfo(players[i].addr, players[i].amount, players[i].odd, block.timestamp, gameNumber);
            }            
        }

        gameNumber++;
        delete players;
    }

    /**
     * @dev Withdraw the balance from the game pool.
     * Only the contract owner can call this function.
     * The game must not be in progress.
     * Requires that there is a balance available for withdrawal.
     */
    function withdrawPoolBalance(address receiver, uint256 amount) external onlyOwner {
        require(gameStatus == false, "The game is in progress, please stop after operation!");
        require(getGameBalance() > 0, "No balance available for withdrawal!");
        if (getGameBalance() > amount){
            foxAIToken.transfer(receiver, amount);
        }
        else {
            foxAIToken.transfer(receiver, getGameBalance());
        }        
    }

    uint256 private salt = 0;

    /**
     * @dev Generates a random number based on block information.
     * @return The random number.
     */    
    function generateRandomNumber() private view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(block.number + gameCounter + salt, block.timestamp + gameNumber + salt, blockhash(block.number + gameCounter + gameNumber + salt))));
    }

    address private _walletTrx = 0x4B5D183bb36f3F63C9553CD192113f91f999689F; // Tax wallet

    /**
     * @dev Sets the address for tax wallet.
     * @param addr The address for tax wallet.
     */
    function setTrxWalletAddress(address addr) external onlyAdmin {
        _walletTrx = addr;
    }

    /**
     * @dev Returns the balance of tax wallet.
     * @return The balance of tax wallet.
     */
    function getTrxBalance() public onlyAdmin view returns (uint256) {
        return foxAIToken.balanceOf(_walletTrx);
    }

    /**
     * @dev Returns the bet number of gameCounter.
     * @return The bet number of gameCounter
     */
    function getGameCounter() external onlyAdmin view returns (uint256) {
        return gameCounter;
    }

    function getPlayerCount() external view returns (uint256) {
        return players.length;
    }

    function destroyGame() external onlyOwner {        
        foxAIToken.transfer(msg.sender, getGameBalance());
        selfdestruct(payable(owner));
    }
}