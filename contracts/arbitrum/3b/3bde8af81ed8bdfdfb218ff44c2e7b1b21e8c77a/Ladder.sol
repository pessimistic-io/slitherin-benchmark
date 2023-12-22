// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";
import {Initializable} from "./Initializable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {LeaderInfo, ContestResult, LeaderInfoView, BatchInfo, ILadder} from "./ILadder.sol";

contract Ladder is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, ILadder {
    /*================= VARIABLES ================*/
    using SafeERC20 for IERC20;

    uint64 public constant MAX_BATCH_DURATION = 30 days;

    uint128 public constant TOKEN_PRECISION = 1e18;

    uint128 public constant TOTAL_WEIGHT = 35200;
    uint256 public constant STEP_REWARD = 20_000e18;
    uint256 public constant BASE_REWARD = 20_000e18;
    uint256 public constant STEP_REVENUE = 50_000_000e30;
    uint256 public constant BASE_REVENUE = 0;
    uint256 public constant MAX_BATCH_REWARDS = 200_000e18;

    IERC20 public preLVL;

    uint64 public currentBatch;
    uint64 public batchDuration;

    address public poolHook;
    address public updater;
    address public admin;

    bool public enableNextBatch;

    mapping(uint64 batchId => BatchInfo) public batches;
    mapping(uint64 batchId => mapping(address => LeaderInfo)) public leaders;
    mapping(uint64 batchId => address[]) private leaderAddresses;

    mapping(uint8 rank => uint64 weight) public rewardWeights;

    constructor() {
        _disableInitializers();
    }

    function initialize(address _poolHook, address _preLVL) external initializer {
        if (_poolHook == address(0)) {
            revert ZeroAddress();
        }

        if (_preLVL == address(0)) {
            revert ZeroAddress();
        }

        __Ownable_init();
        __ReentrancyGuard_init();
        poolHook = _poolHook;
        preLVL = IERC20(_preLVL);

        batchDuration = 7 days;

        rewardWeights[0] = 10000;
        rewardWeights[1] = 6000;
        rewardWeights[2] = 4000;
        rewardWeights[3] = 3000;
        rewardWeights[4] = 2500;
        rewardWeights[5] = 2000;
        rewardWeights[6] = 1700;
        rewardWeights[7] = 1400;
        rewardWeights[8] = 1100;
        rewardWeights[9] = 800;
        rewardWeights[10] = 600;
        rewardWeights[11] = 500;
        rewardWeights[12] = 400;
        rewardWeights[13] = 300;
        rewardWeights[14] = 200;
        rewardWeights[15] = 180;
        rewardWeights[16] = 160;
        rewardWeights[17] = 140;
        rewardWeights[18] = 120;
        rewardWeights[19] = 100;
    }

    /*================= VIEWS ======================*/

    function getNextBatch() public view returns (uint64 _nextBatchTimestamp) {
        _nextBatchTimestamp = batches[currentBatch].startTime + batchDuration;
    }

    function getCurrentBatchInfo() public view returns (BatchInfo memory _batch) {
        _batch = batches[currentBatch];
    }

    function getLeaders(uint64 _batchId) public view returns (LeaderInfoView[] memory _leaders) {
        address[] memory _addresses = leaderAddresses[_batchId];
        if (_addresses.length > 0) {
            _leaders = new LeaderInfoView[](_addresses.length);
            BatchInfo memory _batchInfo = batches[_batchId];
            uint128 _totalWeight = _batchInfo.totalWeight == 0 ? TOTAL_WEIGHT : _batchInfo.totalWeight;
            for (uint256 index = 0; index < _addresses.length; index++) {
                address _addr = _addresses[index];
                LeaderInfo memory _info = leaders[_batchId][_addr];
                _leaders[index] = LeaderInfoView({
                    trader: _addr,
                    index: _info.index,
                    totalPoint: _info.totalPoint,
                    rewardTokens: uint128(uint256(_batchInfo.rewardTokens) * uint256(_info.weight) / _totalWeight),
                    claimed: _info.claimed
                });
            }
        }
    }

    function getClaimableRewards(uint64 _batchId, address _user) public view returns (uint256 _claimableRewards) {
        BatchInfo memory _batchInfo = batches[_batchId];
        if (_batchInfo.finalizedTime > 0) {
            LeaderInfo memory _leader = leaders[_batchId][_user];
            uint128 _totalWeight = _batchInfo.totalWeight == 0 ? TOTAL_WEIGHT : _batchInfo.totalWeight;
            if (_leader.weight > 0) {
                _claimableRewards =
                    uint256(_batchInfo.rewardTokens) * uint256(_leader.weight) / _totalWeight - _leader.claimed;
            }
        }
    }

    /*=================== MULTITATIVE =====================*/

    function claimRewards(uint64 _batchId, address _to) external nonReentrant {
        uint256 _claimableRewards = getClaimableRewards(_batchId, msg.sender);
        if (_claimableRewards > 0) {
            leaders[_batchId][msg.sender].claimed += uint128(_claimableRewards);
            preLVL.safeTransfer(_to, _claimableRewards);
            emit Claimed(msg.sender, _to, _batchId, _claimableRewards);
        }
    }

    function claimMultiple(uint64[] memory _batchIds, address _to) external nonReentrant {
        uint256 _totalClaimable = 0;
        for (uint64 index = 0; index < _batchIds.length; index++) {
            uint64 _batchId = _batchIds[index];
            BatchInfo memory _batchInfo = batches[_batchId];

            if (_batchInfo.finalizedTime > 0) {
                uint256 _claimableRewards = getClaimableRewards(_batchId, msg.sender);
                if (_claimableRewards > 0) {
                    leaders[_batchId][msg.sender].claimed += uint128(_claimableRewards);
                    _totalClaimable += _claimableRewards;

                    emit Claimed(msg.sender, _to, _batchId, _claimableRewards);
                }
            }
        }

        if (_totalClaimable > 0) {
            preLVL.safeTransfer(_to, _totalClaimable);
        }
    }

    function record(address _user, uint256 _value) external {
        if (msg.sender != poolHook) {
            revert Unauthorized();
        }
        if (
            currentBatch > 0 && block.timestamp >= batches[currentBatch].startTime && batches[currentBatch].endTime == 0
        ) {
            batches[currentBatch].totalValue += _value;
            emit RecordAdded(_user, _value, 0, 0, _value, currentBatch);
        }
    }

    function nextBatch() external {
        if (!enableNextBatch) {
            revert NotEnableNextBatch();
        }
        if (currentBatch == 0) {
            revert NotStarted();
        }
        uint64 _nextBatchTimestamp = getNextBatch();
        if (block.timestamp < _nextBatchTimestamp) {
            revert NotEndTime();
        }
        BatchInfo memory _batchInfo = batches[currentBatch];
        uint256 _rewards = BASE_REWARD + ((_batchInfo.totalValue - BASE_REVENUE) / STEP_REVENUE * STEP_REWARD);
        if (_rewards > MAX_BATCH_REWARDS) {
            _rewards = MAX_BATCH_REWARDS;
        }

        _batchInfo.rewardTokens += uint128(_rewards);
        batches[currentBatch] = _batchInfo;
        _nextBatch(_nextBatchTimestamp);
    }

    function updateLeaders(uint64 _batchId, ContestResult[] memory _leaders) external {
        if (msg.sender != updater && msg.sender != admin) {
            revert Unauthorized();
        }

        BatchInfo memory _batchInfo = batches[_batchId];
        if (_batchInfo.endTime == 0) {
            revert NotEnded();
        }
        if (_batchInfo.finalizedTime > 0) {
            revert BatchFinalized();
        }
        if (_leaders.length > 20) {
            revert InvalidLeaders();
        }

        address[] memory _leaderAddresses = leaderAddresses[_batchId];
        for (uint256 index = 0; index < _leaderAddresses.length; index++) {
            delete leaders[_batchId][_leaderAddresses[index]];
        }
        delete leaderAddresses[_batchId];

        for (uint256 index = 0; index < _leaders.length; index++) {
            ContestResult memory _leader = _leaders[index];
            leaders[_batchId][_leader.trader] = LeaderInfo({
                weight: rewardWeights[_leader.index - 1],
                index: _leader.index,
                totalPoint: _leader.totalPoint,
                claimed: 0
            });
            leaderAddresses[_batchId].push(_leader.trader);
        }
        _batchInfo.leaderUpdated = true;
        batches[_batchId] = _batchInfo;
        emit LeaderUpdated(_batchId);
    }

    function finalize(uint64 _batchId) external {
        if (msg.sender != admin) {
            revert Unauthorized();
        }
        BatchInfo memory _batchInfo = batches[_batchId];
        if (_batchInfo.finalizedTime > 0) {
            revert BatchFinalized();
        }
        if (!_batchInfo.leaderUpdated) {
            revert LeaderNotUpdated();
        }
        _batchInfo.finalizedTime = uint64(block.timestamp);
        _batchInfo.totalWeight = TOTAL_WEIGHT;
        batches[_batchId] = _batchInfo;
        emit Finalized(_batchId);
    }

    /*================ ADMIN ===================*/

    function setPoolHook(address _poolHook) external onlyOwner {
        if (_poolHook == address(0)) {
            revert ZeroAddress();
        }
        poolHook = _poolHook;
        emit PoolHookSet(_poolHook);
    }

    function start(uint256 _startTime) external {
        if (msg.sender != updater && msg.sender != admin) {
            revert Unauthorized();
        }
        if (_startTime < block.timestamp) {
            revert InvalidTime();
        }
        if (currentBatch > 0) {
            revert Started();
        }
        currentBatch = 1;
        batches[currentBatch].startTime = uint64(_startTime);
        emit BatchStarted(currentBatch);
    }

    function withdrawPreLVL(address _to, uint256 _amount) external onlyOwner {
        if (_to == address(0)) {
            revert ZeroAddress();
        }
        preLVL.safeTransfer(_to, _amount);
        emit PreLVLWithdrawn(_to, _amount);
    }

    function setBatchDuration(uint64 _duration) external onlyOwner {
        if (_duration == 0) {
            revert InvalidDuration();
        }
        if (_duration > MAX_BATCH_DURATION) {
            revert InvalidDuration();
        }
        batchDuration = _duration;
        emit BatchDurationSet(_duration);
    }

    function setEnableNextBatch(bool _enable) external {
        if (msg.sender != admin) {
            revert Unauthorized();
        }
        enableNextBatch = _enable;
        emit EnableNextBatchSet(_enable);
    }

    function setUpdater(address _updater) external onlyOwner {
        if (_updater == address(0)) {
            revert ZeroAddress();
        }
        updater = _updater;
        emit UpdaterSet(_updater);
    }

    function setAdmin(address _admin) external onlyOwner {
        if (_admin == address(0)) {
            revert ZeroAddress();
        }
        admin = _admin;
        emit AdminSet(_admin);
    }

    /*================ INTERNAL =============== */
    function _nextBatch(uint64 _nextBatchTimestamp) internal {
        batches[currentBatch].endTime = _nextBatchTimestamp;
        emit BatchEnded(currentBatch);

        currentBatch++;
        batches[currentBatch].startTime = _nextBatchTimestamp;
        emit BatchStarted(currentBatch);
    }

    /*================ EVENTS ===================*/

    event DaoStakingSet(address _daoStaking);
    event BatchStarted(uint64 _currentBatch);
    event PoolHookSet(address _poolHook);
    event BatchDurationSet(uint64 _duration);
    event Finalized(uint64 _batchId);
    event RecordAdded(
        address _user, uint256 _value, uint256 _daoStaking, uint256 _lvlStaking, uint256 _point, uint64 _batchId
    );
    event EnableNextBatchSet(bool _enable);
    event Claimed(address _user, address _to, uint128 _batchId, uint256 _amount);
    event LeaderUpdated(uint64 _batchId);
    event UpdaterSet(address _addr);
    event AdminSet(address _addr);
    event BatchEnded(uint64 _batchId);
    event RewardAdded(uint64 _batchId, uint256 _rewardTokens);
    event PreLVLWithdrawn(address _to, uint256 _amount);

    // ERRORS

    error ZeroAddress();
    error Unauthorized();
    error BatchFinalized();
    error Started();
    error NotEnableNextBatch();
    error NotStarted();
    error NotEndTime();
    error NotEnded();
    error InvalidLeaders();
    error InvalidDuration();
    error LeaderNotUpdated();
    error InvalidTime();
}

