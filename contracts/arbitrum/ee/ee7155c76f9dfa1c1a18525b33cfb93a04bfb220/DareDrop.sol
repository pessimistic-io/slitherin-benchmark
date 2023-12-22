// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { SafeTransferLib } from "./SafeTransferLib.sol";
import { ERC20 } from "./ERC20.sol";

interface IRandomizer {
    function request(uint256 callbackGasLimit) external returns (uint256);

    function estimateFee(uint256 callbackGasLimit) external returns (uint256);

    function clientDeposit(address client) external payable;

    function clientWithdrawTo(address to, uint256 amount) external;

    function getFeeStats(uint256 request) external view returns (uint256[2] memory);

    function clientBalanceOf(address _client) external view returns (uint256 deposit, uint256 reserved);

    function getRequest(uint256 request) external view returns (bytes32 result, bytes32 dataHash, uint256 ethPaid, uint256 ethRefunded, bytes10[2] memory vrfHashes);
}

//  @title DareDropContract
//  @dev A contract that facilitates a game in which players dare and win rewards based on random outcomes.

contract DareDropContract {
    using SafeTransferLib for ERC20;


    //   @dev Emitted when ownership of the contract is transferred.
    //   @param user The previous owner's address.
    //   @param newOwner The new owner's address.

    event OwnershipTransferred(address indexed user, address indexed newOwner);


    //  @dev Emitted when a player attempts a dare.
    //  @param user The player's address.
    //  @param wager The wager amount.

    event DareAttempted(address indexed user, uint256 wager);


    //  @dev Emitted when the result of a dare is determined.
    //  @param player The player's address.
    //  @param id The dare's ID.
    //  @param wager The wager amount.
    //  @param result The dare result (true for success, false for failure).

    event DareResult(address indexed player, uint256 indexed id, uint256 wager, bool indexed result);


    //  @dev Emitted when a game is completed.
    //  @param gameId The game's ID.

    event GameCompleted(uint indexed gameId);


    //  @dev Emitted when a user withdraws funds.
    //  @param user The user's address.
    //  @param amount The withdrawn amount.

    event Withdraw(address indexed user, uint amount);


    //  @dev Emitted when a user claims rewards.
    //  @param user The user's address.
    //  @param rewardAmount The claimed reward amount.

    event RewardsClaimed(address indexed user, uint rewardAmount);


    //  @dev Emitted when the gas limit for callback functions is updated.
    //  @param gasLimit The new gas limit.

    event UpdatedGasLimit(uint gasLimit);


    //  @dev Emitted when a user drops funds into the pool.
    //  @param user The user's address.
    //  @param amount The dropped amount.

    event Drop(address indexed user, uint amount);


    //  @dev Emitted when a refund is processed.
    //  @param player The player's address.
    //  @param refundAmount The refunded amount.
    //  @param id The dare's ID.

    event Refund(address indexed player, uint refundAmount, uint indexed id);


    //  @dev Emitted when the lock status is updated.
    //  @param lockStatus The new lock status (0 for unlocked, 1 for locked).

    event LockStatusUpdated(uint8 indexed lockStatus);

    error NoAvailableRefund();
    error InsufficientFunds();
    error OnlyRandomizer();
    error WrongLockStatusForAction();
    error ReentrantCall();
    error AmountZero();
    error AmountTooSmall();
    error InsufficientVRFFee();
    error NoDropPool();
    error GameIncomplete();
    error OnlyOwner();


    // @dev Struct representing a dare.
    // @param wager The wager amount.
    // @param player The player's address.
    // @param result The dare result (true for success, false for failure).
    // @param seed The random seed used to determine the result.

    struct Dare {
        uint wager;
        address player;
        bool result;
        uint256 seed;
    }

    // Map request ID to Dare
    mapping(uint256 => Dare) public dares;

    // Map user address and game ID to balance
    mapping(address => mapping(uint => uint)) public userBalance;

    // Game ID counter
    uint public gameId = 0;

    //  @dev Struct representing the status of a game.
    //  @param rewards The total rewards in the game.
    //  @param poolBalance The current balance in the pool.
    //  @param isGameComplete Indicates if the game is complete (true or false).

    struct GameStatus {
        uint rewards;
        uint poolBalance;
        bool isGameComplete;
    }

    // Map game ID to GameStatus
    mapping(uint => GameStatus) public games;

    // Map user address to the last callback request
    mapping(address => uint256) public userToLastCallback;

    // Map request ID to the payment value for the dare
    mapping(uint256 => uint256) public darePaymentValue;

    // House cut percentage
    uint8 public houseCut;

    // Drop cut percentage
    uint8 public dropCut;

    // Owner address
    address public owner;

    // Immutable reference to the asset token
    ERC20 public immutable ASSET;

    // Immutable reference to the randomizer contract
    IRandomizer public immutable randomizer;

    constructor(address _randomizer, address _asset) {
        houseCut = 5;
        dropCut = 20;
        ASSET = ERC20(_asset);
        randomizer = IRandomizer(_randomizer);
        owner = msg.sender;
        emit OwnershipTransferred(msg.sender, owner);
    }

    // Gas limit for callback functions
    uint256 callbackGasLimit = 400000;

    //  @dev Updates the gas limit for callback functions.
    //  @param gasLimit The new gas limit.

    function updateCallbackGasLimit(uint gasLimit) external onlyOwner {
        callbackGasLimit = gasLimit;
        emit UpdatedGasLimit(gasLimit);
    }


    //  @dev Sets the house cut percentage.
    //  @param _houseCut The new house cut percentage.

    function setHouseCut(uint8 _houseCut) onlyOwner external {
        houseCut = _houseCut;
    }


    // @dev Sets the drop cut percentage.
    // @param _dropCut The new drop cut percentage.

    function setDropCut(uint8 _dropCut) onlyOwner external {
        dropCut = _dropCut;
    }


    //  @dev Modifier that allows only the owner to access a function.

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    // Reentrancy lock
    uint8 private reentrancyLock = 1;


    // @dev Modifier to guard against reentrant calls.

    modifier reentrancyGuard() {
        if (reentrancyLock != 1) revert ReentrantCall();
        reentrancyLock = 2;
        _;
        reentrancyLock = 1;
    }

    // Lock status
    uint8 public lock = 0;


    // @dev Modifier to check and enforce a specific lock status.
    // @param lockStatus The required lock status (0 for unlocked, 1 for locked).

    modifier requiresLockStatus(uint8 lockStatus) {
        if (lock != lockStatus) revert WrongLockStatusForAction();
        _;
    }



    // @dev Retrieves the balance of the current game's pool.
    // @return The balance of the pool.

    function getPoolBalance() view external returns (uint) {
        return (games[gameId].poolBalance);
    }


    // @dev Retrieves the total rewards in the current game.
    // @return The total rewards in the game.

    function getRewards() view external returns (uint) {
        return (games[gameId].rewards);
    }


    // @dev Deposit funds into the pool. Earn yield proportional to total pool share from failed dare attempts.
    // @param _amount The amount to drop into the pool.

    function drop(uint _amount) external reentrancyGuard requiresLockStatus(0) {
        if (_amount == 0) revert AmountZero();
        ERC20(ASSET).safeTransferFrom(msg.sender, address(this), _amount);
        userBalance[msg.sender][gameId] += _amount;
        games[gameId].poolBalance += _amount;
        emit Drop(msg.sender, _amount);
    }


    //  @dev Places a dare with a specified amount and attempts to win the pool.
    //  @param _amount The amount to wager on the dare.
    //  @notice takes a 25% cut. 20% gratuity to the pool, 5% to fees.

    function dare(uint _amount) external payable reentrancyGuard requiresLockStatus(0) {
        if (msg.value < randomizer.estimateFee(callbackGasLimit)) revert InsufficientVRFFee();
        if (_amount == 0) revert AmountZero();
        if (_amount < 100) revert AmountTooSmall();
        if (games[gameId].poolBalance == 0) revert NoDropPool();

        uint _dropCut = (_amount * dropCut / 100);
        uint _houseCut = (_amount * houseCut / 100);
        _amount -= _houseCut;
        ERC20(ASSET).safeTransferFrom(msg.sender, owner, _houseCut);
        ERC20(ASSET).safeTransferFrom(msg.sender, address(this), _amount);
        games[gameId].rewards += _amount;
        // Disable gameplay while dare result is being fetched.
        lock = 1;
        emit LockStatusUpdated(lock);

        // Deposit fee to VRF
        randomizer.clientDeposit{value: msg.value}(address(this));
        // Request random bytes from VRF
        uint id = IRandomizer(randomizer).request(callbackGasLimit);
        // Pair id with dare, document values
        // Remove dropCut from wager value as gratuity to the drop pool.
        _amount -= _dropCut;
        Dare memory _dare = Dare(_amount, msg.sender, false, 0);
        dares[id] = _dare;
        darePaymentValue[id] = msg.value;
        emit DareAttempted(msg.sender, _amount);
    }


    //  @dev Callback function for the randomizer, processes the result of a dare.
    //  @param _id The dare's ID.
    //  @param _value The random value from the randomizer.

    function randomizerCallback(uint _id, bytes32 _value) external reentrancyGuard {
        if (msg.sender != address(randomizer)) revert OnlyRandomizer();
        Dare memory lastDare = dares[_id];
        uint256 seed = uint256(_value);
        bool isDareSuccess = (seed % games[gameId].poolBalance) < lastDare.wager ? true : false;
        lastDare.seed = seed;
        lastDare.result = isDareSuccess;
        dares[_id] = lastDare;

        // Refund leftover VRF fees
        _refund(lastDare.player);
        userToLastCallback[lastDare.player] = _id;
        emit DareResult(lastDare.player, _id, lastDare.wager, isDareSuccess);
        handleDareResult(isDareSuccess, lastDare.player);
    }


    //  @dev Handles the result of a dare and distributes rewards accordingly.
    //  @param _isDareSuccess The result of the dare (true for success, false for failure).
    //  @param darer The player's address.

    function handleDareResult(bool _isDareSuccess, address darer) private {
        if (_isDareSuccess) {
            // Transfer entire pool to the player that made the dare
            ERC20(ASSET).safeTransfer(darer, games[gameId].poolBalance);
            games[gameId].isGameComplete = true;
            emit GameCompleted(gameId);
            ++gameId;
        }

        // Re-enable deposits
        lock = 0;
        emit LockStatusUpdated(lock);
    }


    //  @dev Allows a user to withdraw funds from their balance.
    //  @param _amount The amount to withdraw.
    //  @notice users can only withdraw from current game. 

    function withdraw(uint _amount) external reentrancyGuard requiresLockStatus(0) {
        uint balance = userBalance[msg.sender][gameId];
        if (_amount == 0) revert AmountZero();
        if (_amount > balance) revert InsufficientFunds();
        ERC20(ASSET).safeTransfer(msg.sender, _amount);
        userBalance[msg.sender][gameId] -= _amount;
        games[gameId].poolBalance -= _amount;
        emit Withdraw(msg.sender, _amount);
    }


    //  @dev Allows a user to claim rewards from a completed game.
    //  @param _gameId The ID of the game from which to claim rewards.
    //  @notice can only claim rewards from games already completed.

    function claimRewards(uint _gameId) external reentrancyGuard {
        uint _userBalance = userBalance[msg.sender][_gameId];
        if (_userBalance == 0) revert AmountZero();
        if (!games[_gameId].isGameComplete) revert GameIncomplete();
        if (games[_gameId].rewards == 0) revert InsufficientFunds();

        // Send rewards to the user
        uint _poolBalance = games[_gameId].poolBalance;
        uint _rewards = games[_gameId].rewards;
        uint _userRewards = _rewards * _userBalance / _poolBalance;
        ERC20(ASSET).safeTransfer(msg.sender, _userRewards);
        games[_gameId].rewards -= _userRewards;
        delete userBalance[msg.sender][_gameId];
        emit RewardsClaimed(msg.sender, _userRewards);
    }


    //  @dev Allows a user to request a refund of excess VRF fees.

    function refund() external reentrancyGuard {
        if (!_refund(msg.sender)) revert NoAvailableRefund();
    }


    //  @dev Internal function to process a refund of excess VRF fees to a player.
    //  @param _player The player's address.
    //  @return A boolean indicating if the refund was successful.

    function _refund(address _player) private returns (bool) {
        uint256 refundableId = userToLastCallback[_player];
        if (refundableId > 0) {
            uint256[2] memory feeStats = randomizer.getFeeStats(refundableId);
            if (darePaymentValue[refundableId] > feeStats[0]) {
                // Refund 90% of the excess deposit to the player
                uint256 refundAmount = darePaymentValue[refundableId] - feeStats[0];
                refundAmount = refundAmount * 9/10;
                (uint256 ethDeposit, uint256 ethReserved) = randomizer.clientBalanceOf(address(this));
                if (refundAmount <= ethDeposit - ethReserved) {
                    // Refund the excess deposit to the player
                    randomizer.clientWithdrawTo(_player, refundAmount);
                    emit Refund(_player, refundAmount, refundableId);
                    return true;
                }
            }
        }
        return false;
    }

    //  @dev Allows the owner to change the lock status for emergency purposes.

    function emergencyChangeLockStatus() external onlyOwner {
        if (lock == 0) lock = 1;
        else if (lock == 1) lock = 0;
    }


    //  @dev Allows the owner to transfer ownership of the contract.
    //  @param newOwner The new owner's address.

    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
        emit OwnershipTransferred(msg.sender, newOwner);
    }

    // @dev Fallback function to receive Ether.

    receive() external payable {
    }

}

