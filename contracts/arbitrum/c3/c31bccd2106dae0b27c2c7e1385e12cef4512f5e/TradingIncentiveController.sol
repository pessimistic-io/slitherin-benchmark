// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {Initializable} from "./Initializable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {ILVLTwapOracle} from "./ILVLTwapOracle.sol";
import {ILyLevel} from "./ILyLevel.sol";
import {ITradingContest} from "./ITradingContest.sol";
import {ITradingIncentiveController} from "./ITradingIncentiveController.sol";

/**
 * @title ITradingIncentiveController
 * @author LevelFinance
 * @notice Tracking protocol fee and calculate incentive reward in a period of time called batch.
 * Once a batch finished, incentive distributed to lyLVL and Ladder
 */
contract TradingIncentiveController is Initializable, OwnableUpgradeable, ITradingIncentiveController {
    /*================= VARIABLES ================*/
    using SafeERC20 for IERC20;

    IERC20 public constant LVL = IERC20(0xB64E280e9D1B5DbEc4AcceDb2257A87b400DB149);
    IERC20 public constant PRE_LVL = IERC20(0x7E416685d5dFB54cF0F6258E5b2c1953F7390Ff0);

    uint256 public constant MIN_EPOCH_DURATION = 1 days;
    uint256 public constant MAX_REWARD_TOKENS = 15_000e18;
    uint256 public constant STEP_REVENUE = 50_000e30;
    uint256 public constant BASE_REVENUE = 100_000e30;
    uint256 public constant STEP_REWARD = 10_000e30;
    uint256 public constant AMOUNT_LOYALTY_REWARD = 5_000e18;
    uint256 public constant START_EPOCH_USING_PRE_LVL = 56; // arb

    uint256 public currentEpoch;
    uint256 public lastEpochTimestamp;
    uint256 public epochDuration;
    uint256 public epochFee;

    address public poolHook;
    address public admin;
    ILVLTwapOracle public lvlOracle;
    ILyLevel public lyLevel;
    ITradingContest public tradingContest;

    constructor() {
        _disableInitializers();
    }

    function initialize(address _lvlOracle, address _poolHook, address _tradingContest, address _lyLevel)
        external
        initializer
    {
        require(_lvlOracle != address(0), "Invalid address");
        require(_poolHook != address(0), "Invalid address");
        require(_tradingContest != address(0), "Invalid address");
        require(_lyLevel != address(0), "Invalid address");

        __Ownable_init();
        lvlOracle = ILVLTwapOracle(_lvlOracle);
        lvlOracle.update();
        poolHook = _poolHook;
        tradingContest = ITradingContest(_tradingContest);
        lyLevel = ILyLevel(_lyLevel);
        emit PoolHookSet(_poolHook);
        emit TradingContestSet(_tradingContest);
        emit LyLevelSet(_lyLevel);
    }

    /*=================== MUTATIVE =====================*/

    /**
     * @inheritdoc ITradingIncentiveController
     */
    function record(uint256 _value) external {
        require(msg.sender == poolHook, "Only poolHook");
        if (block.timestamp >= lastEpochTimestamp) {
            epochFee += _value;
        }
    }

    /**
     * @inheritdoc ITradingIncentiveController
     */
    function allocate() external {
        require(msg.sender == admin, "!Admin");
        require(lastEpochTimestamp > 0, "Not started");

        uint256 _nextEpochTimestamp = lastEpochTimestamp + epochDuration;
        require(block.timestamp >= _nextEpochTimestamp, "now < trigger time");
        lvlOracle.update();
        uint256 _twap = lvlOracle.lastTWAP();

        IERC20 _rewardToken = currentEpoch >= START_EPOCH_USING_PRE_LVL ? PRE_LVL : LVL;
        _rewardToken.safeIncreaseAllowance(address(lyLevel), AMOUNT_LOYALTY_REWARD);
        lyLevel.addReward(AMOUNT_LOYALTY_REWARD);

        uint256 _contestRewards;
        if (epochFee >= BASE_REVENUE) {
            uint256 _rewards = ((epochFee - BASE_REVENUE) / STEP_REVENUE + 1) * STEP_REWARD;

            _contestRewards = _rewards / _twap;
            if (_contestRewards > MAX_REWARD_TOKENS - AMOUNT_LOYALTY_REWARD) {
                _contestRewards = MAX_REWARD_TOKENS - AMOUNT_LOYALTY_REWARD;
            }
            _rewardToken.safeIncreaseAllowance(address(tradingContest), _contestRewards);
        }
        tradingContest.addReward(_contestRewards);

        emit Allocated(currentEpoch, epochFee, _contestRewards, AMOUNT_LOYALTY_REWARD);
        epochFee = 0;
        lastEpochTimestamp = _nextEpochTimestamp;

        currentEpoch++;
        emit EpochStarted(currentEpoch, _nextEpochTimestamp);
    }

    /**
     * @inheritdoc ITradingIncentiveController
     */
    function start(uint256 _startTime) external {
        require(lastEpochTimestamp == 0, "started");
        require(_startTime >= block.timestamp, "start time < current time");
        lastEpochTimestamp = _startTime;
        lvlOracle.update();
        emit EpochStarted(currentEpoch, _startTime);
    }

    /*================ ADMIN ===================*/

    function setEpochDuration(uint256 _epochDuration) public onlyOwner {
        require(_epochDuration >= MIN_EPOCH_DURATION, "must >= MIN_EPOCH_DURATION");
        epochDuration = _epochDuration;
        emit EpochDurationSet(epochDuration);
    }

    function setPoolHook(address _poolHook) external onlyOwner {
        require(_poolHook != address(0), "Invalid address");
        poolHook = _poolHook;
        emit PoolHookSet(_poolHook);
    }

    function setAdmin(address _admin) external onlyOwner {
        require(_admin != address(0), "Invalid address");
        admin = _admin;
        emit AdminSet(_admin);
    }

    function withdrawLVL(address _to, uint256 _amount) external onlyOwner {
        require(_to != address(0), "Invalid address");
        LVL.safeTransfer(_to, _amount);
        emit LVLWithdrawn(_to, _amount);
    }

    function withdrawPreLVL(address _to, uint256 _amount) external onlyOwner {
        require(_to != address(0), "Invalid address");
        PRE_LVL.safeTransfer(_to, _amount);
        emit PreLVLWithdrawn(_to, _amount);
    }

    /*================ EVENTS ===================*/
    event TradingContestSet(address _addr);
    event LyLevelSet(address _addr);
    event PoolHookSet(address _addr);
    event OracleSet(address _oracle);
    event Allocated(uint256 _epoch, uint256 _totalFee, uint256 _contestReward, uint256 _loyaltyRewards);
    event LVLWithdrawn(address _to, uint256 _amount);
    event EpochDurationSet(uint256 _duration);
    event AdminSet(address _admin);
    event EpochStarted(uint256 _epoch, uint256 _timeStart);
    event LoyaltyRewardSet(uint256 _rewards);
    event PreLVLWithdrawn(address _to, uint256 _amount);
}

