//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./IERC20.sol";

interface IRandomizer {
    function request(uint256 callbackGasLimit) external returns (uint256);
    function request(uint256 callbackGasLimit, uint256 confirmations) external returns (uint256);
    function clientWithdrawTo(address _to, uint256 _amount) external;
    function estimateFee(uint256 callbackGasLimit) external returns (uint256);
    function estimateFee(uint256 callbackGasLimit, uint256 confirmations) external returns (uint256);
}

// Coinflip contract
contract CoinFlipTest is Ownable, ReentrancyGuard {
    struct UserInfo {
        address user;
        uint256 userBet;
        uint256 time;
        bool isTail;
    }

    // Arbitrum
    IRandomizer public randomizer = IRandomizer(0x5b8bB80f2d72D0C85caB8fB169e8170A05C94bAF);

    IERC20 public immutable token;

    // Stores each game to the player
    mapping(uint256 => UserInfo) public flipToAddress;
    mapping(address => uint256) public addressToFlip;

    bool public pause;

    uint256 public callbackGasLimit = 500000;
    uint256 public minBet = 1 * 1e6;
    uint256 public rewardPool;
    uint256 public rewardPoolDenominator = 1000; //0.1% from reward pool supply
    uint256 public refundDelay = 10;
    uint256 private tempStorage;

    // Events
    event NewFlip(address indexed user, uint256 amount, bool isTail, uint256 gameId);
    event Win(address indexed winner, uint256 amount, uint256 gameId);
    event Lose(address indexed loser, uint256 amount, uint256 gameId);
    event Cancel(address indexed user, uint256 amount, uint256 gameId);
    event CallbackGasLimitUpdated(uint256 oldValue, uint256 newValue);
    event SettingsUpdated(uint256 newDenominator, uint256 newDelay);
    event PauseChanged(bool newState);

    constructor(address _token) {
        token = IERC20(_token);
    }

    function maxBet() public view returns (uint256) {
        return rewardPool / rewardPoolDenominator;
    }

    function addToRewardPool(uint256 amount) external onlyOwner {
        require(token.transferFrom(msg.sender, address(this), amount), "TOKEN TRANSFER FAILED");
        rewardPool += amount;
    }

    // The coin flip containing the random request
    function flip(uint256 userBet, bool isTail) external payable returns (uint256) {
        require(!pause, "game paused");
        require(addressToFlip[msg.sender] == 0, "user have pending game");
        uint256 fee = randomizer.estimateFee(callbackGasLimit);
        require(msg.value >= fee, "INSUFFICIENT ETH AMOUNT PROVIDED");
        require(minBet <= userBet && userBet <= maxBet(), "WRONG BET");
        require(token.transferFrom(msg.sender, address(this), userBet), "TOKEN TRANSFER FAILED");

        uint256 id = randomizer.request(callbackGasLimit);
        flipToAddress[id] = UserInfo(msg.sender, userBet, block.timestamp, isTail);

        tempStorage += userBet;
        rewardPool -= userBet;

        uint256 refund = msg.value - fee;
        (bool success, ) = payable(msg.sender).call{ value: refund }("");
        require(success, "Can't send ETH");

        emit NewFlip(msg.sender, userBet, isTail, id);

        return id;
    }

    // Callback function called by the randomizer contract when the random value is generated
    function randomizerCallback(uint256 _id, bytes32 _value) external {
        require(msg.sender == address(randomizer), "Caller not Randomizer");

        UserInfo storage player = flipToAddress[_id];
        uint256 random = uint256(_value) % 99;
        // If the random number is less than 50 - tail
        bool result = (random < 50);
        if (player.isTail == result) {
            tempStorage -= player.userBet;
            token.transfer(player.user, player.userBet*2);
            emit Win(player.user, player.userBet*2, _id);
        } else {
            tempStorage -= player.userBet;
            rewardPool += player.userBet*2;
            emit Lose(player.user, player.userBet, _id);
        }

        delete addressToFlip[player.user];
        delete flipToAddress[_id];
    }

    function getRefund() external nonReentrant {
        uint256 id = addressToFlip[msg.sender];
        require(id != 0, "no pending games");

        UserInfo storage player = flipToAddress[id];
        require(block.timestamp >= player.time + refundDelay);

        token.transfer(player.user, player.userBet);
        tempStorage -= player.userBet;
        rewardPool += player.userBet;

        emit Cancel(player.user, player.userBet, id);

        delete flipToAddress[id];
        delete addressToFlip[msg.sender];
    }

    function changeCallbackGasLimit(uint256 newLimit) external onlyOwner {
        uint256 oldValue = callbackGasLimit;
        callbackGasLimit = newLimit;
        emit CallbackGasLimitUpdated(oldValue, newLimit);
    }

    // Allows the owner to withdraw their deposited randomizer funds
    function randomizerWithdraw(uint256 amount) external onlyOwner {
        require(amount > 0, "invalid amount");
        randomizer.clientWithdrawTo(msg.sender, amount);
    }

    function changeSettings(uint256 newDenominator, uint256 newDelay) external onlyOwner {
        require(newDenominator > 0, "invalid new denominator");
        require(newDelay > 0, "invalid new delay");
        rewardPoolDenominator = newDenominator;
        refundDelay = newDelay;
        emit SettingsUpdated(newDenominator, newDelay);
    }

    function setPause(bool state) external onlyOwner {
        pause = state;
        emit PauseChanged(state);
    }

    function withdraw(address _token, uint256 _amount) external onlyOwner {
        if (_token != address(0)) {
            if (_token == address(token)) {
                require(_amount <= rewardPool, "amount exceeded remain reward pool");
                rewardPool -= _amount;
            }
			IERC20(_token).transfer(msg.sender, _amount);
		} else {
			(bool success, ) = payable(msg.sender).call{ value: _amount }("");
			require(success, "Can't send ETH");
		}
	}
}
