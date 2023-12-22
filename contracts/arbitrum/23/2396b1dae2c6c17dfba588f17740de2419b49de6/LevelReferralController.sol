// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import {Initializable} from "./Initializable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {ILevelReferralRegistry} from "./ILevelReferralRegistry.sol";
import {ILVLTwapOracle} from "./ILVLTwapOracle.sol";

contract LevelReferralController is Initializable, OwnableUpgradeable {
    struct EpochInfo {
        uint64 startTime;
        uint64 endTime;
        uint128 lvlTWAP;
        uint256 totalFee;
    }

    uint256 public constant MIN_EPOCH_DURATION = 1 days;

    ILevelReferralRegistry public referralRegistry;
    ILVLTwapOracle public oracle;

    /// @dev epoch -> epochInfo
    mapping(uint256 epoch => EpochInfo info) public epochs;
    /// @dev epoch -> user -> fee
    mapping(uint256 epoch=> mapping(address user=> uint256 fee)) public users;

    address public poolHook;
    address public distributor;

    uint256 public currentEpoch;
    uint256 public lastEpochTimestamp;
    uint256 public epochDuration;

    bool public enableNextEpoch;
    address public orderHook;

    constructor() {
        _disableInitializers();
    }

    function initialize(address _oracle, address _levelRegistry, uint256 _epochDuration) external initializer {
        require(_oracle != address(0), "invalid address");
        require(_levelRegistry != address(0), "invalid address");
        require(_epochDuration >= MIN_EPOCH_DURATION, "_epochDuration < MIN_EPOCH_DURATION");
        __Ownable_init();
        referralRegistry = ILevelReferralRegistry(_levelRegistry);
        epochDuration = _epochDuration;
        oracle = ILVLTwapOracle(_oracle);
        oracle.update();
    }

    // =============== VIEW FUNCTIONS ===============

    function getNextEpoch() public view returns (uint256 _nextEpochTimestamp) {
        _nextEpochTimestamp = lastEpochTimestamp + epochDuration;
    }

    // =============== USER FUNCTIONS ===============
    function setReferrer(address _referrer) external {
        _setReferrer(msg.sender, _referrer);
    }

    function setReferrer(address _trader, address _referrer) external {
        require(msg.sender == orderHook, "!onlyOrderHook");
        if (_trader != _referrer && referralRegistry.referredBy(_trader) == address(0)) {
            _setReferrer(_trader, _referrer);
        }
    }

    function updateFee(address _trader, uint256 _fee) external {
        require(msg.sender == poolHook, "!poolHook");
        if(currentEpoch > 0 && block.timestamp >= lastEpochTimestamp && _trader != address(0) && _fee > 0) {
            users[currentEpoch][_trader] += _fee;
            epochs[currentEpoch].totalFee += _fee;
            emit TradingFeeUpdated(currentEpoch, _trader, _fee);
        }
    }

    function nextEpoch() external {
        require(enableNextEpoch, "!enableNextEpoch");
        uint256 nextEpochTimestamp = getNextEpoch();
        require(block.timestamp >= nextEpochTimestamp, "now < trigger time");

        oracle.update();
        epochs[currentEpoch].endTime = uint64(nextEpochTimestamp);
        epochs[currentEpoch].lvlTWAP = uint128(oracle.lastTWAP());
        lastEpochTimestamp = nextEpochTimestamp;
        emit EpochEnded(currentEpoch);

        currentEpoch++;
        epochs[currentEpoch].startTime = uint64(nextEpochTimestamp);
        emit EpochStarted(currentEpoch, uint64(nextEpochTimestamp));
    }

    function start(uint256 _startTime) external onlyOwner {
        // call once when switch controller
        require(lastEpochTimestamp == 0, "started");
        oracle.update();
        lastEpochTimestamp = _startTime;
        currentEpoch = 24; // start where controller v2 stop
        epochs[currentEpoch].startTime = uint64(_startTime);
        emit EpochStarted(currentEpoch, uint64(_startTime));
    }

    // =============== RESTRICTED ===============

    function setDistributor(address _distributor) external onlyOwner {
        require(_distributor != address(0), "invalid address");
        distributor = _distributor;
        emit DistributorSet(distributor);
    }

    function setPoolHook(address _poolHook) external onlyOwner {
        require(_poolHook != address(0), "invalid address");
        poolHook = _poolHook;
        emit PoolHookSet(_poolHook);
    }

    function setEpochDuration(uint256 _epochDuration) public onlyOwner {
        require(_epochDuration >= MIN_EPOCH_DURATION, "_epochDuration < MIN_EPOCH_DURATION");
        epochDuration = _epochDuration;
        emit EpochDurationSet(epochDuration);
    }

    function setEnableNextEpoch(bool _enable) external {
        require(msg.sender == distributor, "!distributor");
        enableNextEpoch = _enable;
        emit EnableNextEpochSet(_enable);
    }

    function setOrderHook(address _orderHook) external onlyOwner {
        require(_orderHook != address(0), "invalid address");
        orderHook = _orderHook;
        emit OrderHookSet(_orderHook);
    }

    function setOracle(address _oracle) external onlyOwner {
        require(_oracle != address(0) && _oracle != address(oracle), "invalid address");
        oracle = ILVLTwapOracle(_oracle);
        oracle.update();
        emit OracleSet(_oracle);
    }

    // =============== INTERNAL FUNCTIONS ===============

    function _setReferrer(address _trader, address _referrer) internal {
        referralRegistry.setReferrer(_trader, _referrer);
    }

    // ===============  EVENTS ===============
    event TradingFeeUpdated(uint256 indexed epoch, address indexed trader, uint256 fee);
    event EpochStarted(uint256 indexed epoch, uint64 startTime);
    event EpochDurationSet(uint256 epochDuration);
    event PoolHookSet(address indexed poolHook);
    event EnableNextEpochSet(bool enable);
    event OrderHookSet(address orderHook);
    event DistributorSet(address indexed distributor);
    event EpochEnded(uint256 indexed epoch);
    event OracleSet(address indexed updater);
}

