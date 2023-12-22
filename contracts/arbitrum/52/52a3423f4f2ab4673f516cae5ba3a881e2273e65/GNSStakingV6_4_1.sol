// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Initializable.sol";
import "./Ownable2StepUpgradeable.sol";
import "./GNSStakingInterfaceV6_4_1.sol";
import "./TokenInterfaceV5.sol";

contract GNSStakingV6_4_1 is Initializable, Ownable2StepUpgradeable, GNSStakingInterfaceV6_4_1 {
    // Constants
    uint48 private constant MAX_UNLOCK_DURATION = 730 days; // 2 years in seconds
    uint128 private constant MIN_UNLOCK_GNS_AMOUNT = 1e18;

    // Contracts & Addresses
    TokenInterfaceV5 public gns; // GNS
    TokenInterfaceV5 public dai;

    // Pool state
    uint128 public accDaiPerToken;
    uint128 public gnsBalance;

    // Mappings
    mapping(address => Staker) public stakers;
    mapping(address => UnlockSchedule[]) private unlockSchedules;
    mapping(address => bool) public unlockManagers; // addresses allowed to create unlock schedules for others

    // Events
    event UnlockManagerUpdated(address indexed manager, bool authorized);

    event DaiDistributed(uint amountDai);
    event DaiHarvested(address indexed staker, uint128 amountDai);
    event DaiHarvestedFromUnlock(address indexed staker, uint[] ids, uint128 amountDai);

    event GnsStaked(address indexed staker, uint128 amountGns);
    event GnsUnstaked(address indexed staker, uint128 amountGns);
    event GnsClaimed(address indexed staker, uint[] ids, uint128 amountGns);

    event UnlockScheduled(address indexed staker, uint indexed index, UnlockSchedule schedule);
    event UnlockScheduleRevoked(address indexed staker, uint indexed index);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner, TokenInterfaceV5 _gns, TokenInterfaceV5 _dai) external initializer {
        require(
            address(_owner) != address(0) && address(_gns) != address(0) && address(_dai) != address(0),
            "WRONG_PARAMS"
        );

        _transferOwnership(_owner);
        gns = _gns;
        dai = _dai;
    }

    //
    // Modifiers
    //

    modifier onlyAuthorizedUnlockManager(address _staker, bool _revocable) {
        require(
            (_staker == msg.sender && !_revocable) || msg.sender == owner() || unlockManagers[msg.sender],
            "NO_AUTH"
        );
        _;
    }

    //
    // Management functions
    //

    function setUnlockManager(address _manager, bool _authorized) external onlyOwner {
        unlockManagers[_manager] = _authorized;

        emit UnlockManagerUpdated(_manager, _authorized);
    }

    //
    // Internal view functions
    //

    function _currentDebtDai(uint128 _staked) private view returns (uint128) {
        return uint128((uint(_staked) * accDaiPerToken) / 1e18);
    }

    function _pendingDai(uint128 _staked, uint128 _debtDai) private view returns (uint128) {
        return _currentDebtDai(_staked) - _debtDai;
    }

    function _pendingDai(UnlockSchedule memory _schedule) private view returns (uint128) {
        return _currentDebtDai(_schedule.totalGns - _schedule.claimedGns) - _schedule.debtDai;
    }

    //
    // Public view functions
    //

    function unlockedGns(UnlockSchedule memory _schedule, uint48 _timestamp) public pure returns (uint128) {
        // if unlock schedule has ended return totalGns
        if (_timestamp >= _schedule.start + _schedule.duration) return _schedule.totalGns;

        // if unlock hasn't started or it's a cliff unlock return 0
        if (_timestamp < _schedule.start || _schedule.unlockType == UnlockType.CLIFF) return 0;

        return uint128((uint(_schedule.totalGns) * (_timestamp - _schedule.start)) / _schedule.duration);
    }

    function releasableGns(UnlockSchedule memory _schedule, uint48 _timestamp) public pure returns (uint128) {
        return unlockedGns(_schedule, _timestamp) - _schedule.claimedGns;
    }

    function owner() public view override(GNSStakingInterfaceV6_4_1, OwnableUpgradeable) returns (address) {
        return super.owner();
    }

    //
    // Internal state-modifying functions
    //

    function _harvestDaiFromUnlock(address _staker, uint[] memory _ids) private {
        require(_staker != address(0), "USER_EMPTY");
        require(_ids.length > 0, "IDS_EMPTY");

        uint128 pendingDai;

        for (uint i; i < _ids.length; ) {
            UnlockSchedule storage schedule = unlockSchedules[_staker][_ids[i]];

            uint128 newDebtDai = _currentDebtDai(schedule.totalGns - schedule.claimedGns);
            uint128 newRewardsDai = newDebtDai - schedule.debtDai;

            pendingDai += newRewardsDai;
            schedule.debtDai = newDebtDai;

            unchecked {
                ++i;
            }
        }

        dai.transfer(_staker, uint(pendingDai));

        emit DaiHarvestedFromUnlock(_staker, _ids, pendingDai);
    }

    function _claimUnlockedGns(address _staker, uint48 _timestamp, uint[] memory _ids) private {
        uint128 claimedGns;

        _harvestDaiFromUnlock(_staker, _ids);

        for (uint i; i < _ids.length; ) {
            UnlockSchedule storage schedule = unlockSchedules[_staker][_ids[i]];
            uint128 amountGns = releasableGns(schedule, _timestamp);

            schedule.claimedGns += amountGns;
            assert(schedule.claimedGns <= schedule.totalGns);
            schedule.debtDai = _currentDebtDai(schedule.totalGns - schedule.claimedGns);

            claimedGns += amountGns;

            unchecked {
                ++i;
            }
        }

        gnsBalance -= claimedGns;
        gns.transfer(_staker, uint(claimedGns));

        emit GnsClaimed(_staker, _ids, claimedGns);
    }

    //
    // Public/External interaction functions
    //

    function distributeRewardDai(uint _amountDai) external override {
        require(gnsBalance > 0, "NO_GNS_STAKED");

        dai.transferFrom(msg.sender, address(this), _amountDai);
        accDaiPerToken += uint128((_amountDai * 1e18) / gnsBalance);

        emit DaiDistributed(_amountDai);
    }

    function harvestDai() public {
        Staker storage staker = stakers[msg.sender];

        uint128 newDebtDai = _currentDebtDai(staker.stakedGns);
        uint128 pendingDai = newDebtDai - staker.debtDai;

        staker.debtDai = newDebtDai;
        dai.transfer(msg.sender, uint(pendingDai));

        emit DaiHarvested(msg.sender, pendingDai);
    }

    function harvestDaiFromUnlock(uint[] calldata _ids) external {
        _harvestDaiFromUnlock(msg.sender, _ids);
    }

    function harvestDaiAll(uint[] calldata _ids) external {
        harvestDai();
        _harvestDaiFromUnlock(msg.sender, _ids);
    }

    function stakeGns(uint128 _amountGns) external {
        require(_amountGns > 0, "AMOUNT_ZERO");

        gns.transferFrom(msg.sender, address(this), uint(_amountGns));

        harvestDai();

        Staker storage staker = stakers[msg.sender];
        staker.stakedGns += _amountGns;
        staker.debtDai = _currentDebtDai(staker.stakedGns);

        gnsBalance += _amountGns;

        emit GnsStaked(msg.sender, _amountGns);
    }

    function unstakeGns(uint128 _amountGns) external {
        require(_amountGns > 0, "AMOUNT_ZERO");

        harvestDai();

        Staker storage staker = stakers[msg.sender];
        staker.stakedGns -= _amountGns;
        staker.debtDai = _currentDebtDai(staker.stakedGns);

        gnsBalance -= _amountGns;

        gns.transfer(msg.sender, uint(_amountGns));

        emit GnsUnstaked(msg.sender, _amountGns);
    }

    function claimUnlockedGns(uint[] memory _ids) external {
        _claimUnlockedGns(msg.sender, uint48(block.timestamp), _ids);
    }

    function createUnlockSchedule(
        UnlockScheduleInput calldata _schedule,
        address _staker
    ) external override onlyAuthorizedUnlockManager(_staker, _schedule.revocable) {
        uint48 timestamp = uint48(block.timestamp);

        require(_schedule.start < timestamp + MAX_UNLOCK_DURATION, "TOO_FAR_IN_FUTURE");
        require(_schedule.duration > 0 && _schedule.duration <= MAX_UNLOCK_DURATION, "INCORRECT_DURATION");
        require(_schedule.totalGns >= MIN_UNLOCK_GNS_AMOUNT, "INCORRECT_AMOUNT");
        require(_staker != address(0), "ADDRESS_0");

        uint128 totalGns = _schedule.totalGns;

        // Requester has to pay the gns amount
        gns.transferFrom(msg.sender, address(this), uint(totalGns));

        UnlockSchedule memory schedule = UnlockSchedule({
            totalGns: totalGns,
            claimedGns: 0,
            debtDai: _currentDebtDai(totalGns),
            start: _schedule.start >= timestamp ? _schedule.start : timestamp, // accept time in the future
            duration: _schedule.duration,
            unlockType: _schedule.unlockType,
            revocable: _schedule.revocable,
            __placeholder: 0
        });

        unlockSchedules[_staker].push(schedule);
        gnsBalance += totalGns;

        emit UnlockScheduled(_staker, unlockSchedules[_staker].length - 1, schedule);
    }

    function revokeUnlockSchedule(address _staker, uint _id) external onlyOwner {
        UnlockSchedule storage schedule = unlockSchedules[_staker][_id];
        require(schedule.revocable, "NOT_REVOCABLE");

        uint[] memory ids = new uint[](1);
        ids[0] = _id;

        // claims unlocked gns and harvests pending rewards
        _claimUnlockedGns(_staker, uint48(block.timestamp), ids);

        uint128 lockedAmountGns = schedule.totalGns - schedule.claimedGns;

        // resets unlockSchedule so no more claims or harvests are possible
        schedule.totalGns = schedule.claimedGns;
        schedule.duration = 0;
        schedule.start = 0;
        schedule.debtDai = 0;

        gnsBalance -= lockedAmountGns;

        gns.transfer(owner(), uint(lockedAmountGns));

        emit UnlockScheduleRevoked(_staker, _id);
    }

    //
    // External view functions
    //

    function pendingRewardDai(address _staker) external view returns (uint128) {
        Staker memory staker = stakers[_staker];

        return _pendingDai(staker.stakedGns, staker.debtDai);
    }

    function pendingRewardDaiFromUnlocks(address _staker) external view returns (uint128 pending) {
        UnlockSchedule[] memory stakerUnlocks = unlockSchedules[_staker];

        for (uint i; i < stakerUnlocks.length; ) {
            pending += _pendingDai(stakerUnlocks[i]);

            unchecked {
                ++i;
            }
        }
    }

    function pendingRewardDaiFromUnlocks(
        address _staker,
        uint[] calldata _ids
    ) external view returns (uint128 pending) {
        for (uint i; i < _ids.length; ) {
            pending += _pendingDai(unlockSchedules[_staker][_ids[i]]);

            unchecked {
                ++i;
            }
        }
    }

    function totalGnsStaked(address _staker) external view returns (uint128) {
        uint128 totalGns = stakers[_staker].stakedGns;
        UnlockSchedule[] memory stakerUnlocks = unlockSchedules[_staker];

        for (uint i; i < stakerUnlocks.length; ) {
            UnlockSchedule memory schedule = stakerUnlocks[i];
            totalGns += schedule.totalGns - schedule.claimedGns;

            unchecked {
                ++i;
            }
        }

        return totalGns;
    }

    function getUnlockSchedules(address _staker) external view returns (UnlockSchedule[] memory) {
        return unlockSchedules[_staker];
    }

    function getUnlockSchedules(address _staker, uint _index) external view returns (UnlockSchedule memory) {
        return unlockSchedules[_staker][_index];
    }
}

