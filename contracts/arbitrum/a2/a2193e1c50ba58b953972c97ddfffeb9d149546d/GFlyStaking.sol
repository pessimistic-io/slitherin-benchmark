// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./AccessControlUpgradeable.sol";
import "./Initializable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./EnumerableSetUpgradeable.sol";
import "./IGFlyStaking.sol";
import "./IGFly.sol";

//MMMMWKl.                                            .:0WMMMM//
//MMMWk,                                                .dNMMM//
//MMNd.                                                  .lXMM//
//MWd.    .','''....                         .........    .lXM//
//Wk.     ';......'''''.                ..............     .dW//
//K;     .;,         ..,'.            ..'..         ...     'O//
//d.     .;;.           .''.        ..'.            .'.      c//
//:       .','.           .''.    ..'..           ....       '//
//'         .';.            .''...'..           ....         .//
//.           ';.             .''..             ..           .//
//.            ';.                             ...           .//
//,            .,,.                           .'.            .//
//c             .;.                           '.             ;//
//k.            .;.             .             '.            .d//
//Nl.           .;.           .;;'            '.            :K//
//MK:           .;.          .,,',.           '.           'OW//
//MM0;          .,,..       .''  .,.       ...'.          'kWM//
//MMMK:.          ..'''.....'..   .'..........           ,OWMM//
//MMMMXo.             ..'...        ......             .cKMMMM//
//MMMMMWO:.                                          .,kNMMMMM//
//MMMMMMMNk:.                                      .,xXMMMMMMM//
//MMMMMMMMMNOl'.                                 .ckXMMMMMMMMM//

contract GFlyStaking is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, IGFlyStaking {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    /// @dev The identifier of the role which maintains other roles.
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");
    /// @dev The identifier of the role which allows accounts to run cron jobs.
    bytes32 public constant BATTLEFLY_BOT_ROLE = keccak256("BATTLEFLY_BOT");
    /// @dev The identifier of the role which allows accounts to manage vestings.
    bytes32 public constant VESTING_MANAGER_ROLE = keccak256("VESTING_MANAGER");

    bool public pause;
    uint16 public currentEpoch;
    uint256 public currentStakeId;
    uint256 public nextCron;
    uint256[36] public emissionsAtMonth;

    IGFly public gFly;

    mapping(uint16 => uint256) public unlockableAtEpoch;
    mapping(uint16 => uint256) public miningPowerAtEpoch;
    mapping(uint256 => GFlyStake) public stakeById;
    mapping(address => EnumerableSetUpgradeable.UintSet) private stakeIdsByAddress;
    mapping(uint256 => bool) public cronExecuted;

    // Extension for non-multisig guardians
    mapping(address => bool) public guardian;

    // Extension for lock auto-increasing
    mapping(uint16 => uint256) public autoIncreasedForLocks;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address gFly_, address dao, address battleflyBot, uint256 nextCron_) external initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();

        require(gFly_ != address(0), "GFlyStaking:INVALID_ADDRESS");
        require(dao != address(0), "GFlyStaking:INVALID_ADDRESS");
        require(battleflyBot != address(0), "GFlyStaking:INVALID_ADDRESS");

        _setupRole(ADMIN_ROLE, dao);
        _setupRole(ADMIN_ROLE, msg.sender); // This will be surrendered after deployment
        _setupRole(BATTLEFLY_BOT_ROLE, battleflyBot);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(BATTLEFLY_BOT_ROLE, ADMIN_ROLE);
        _setRoleAdmin(VESTING_MANAGER_ROLE, ADMIN_ROLE);

        gFly = IGFly(gFly_);

        currentEpoch = 1;
        pause = true;
        nextCron = nextCron_;
        _setEmissions();
    }

    modifier whenNotPaused() {
        require(!pause, "GFlyStaking:PAUSED");
        _;
    }

    modifier onlyAvailableLock(uint256 lock) {
        require(lock >= 1 && lock <= 365, "GFlyStaking:UNALLOWED_LOCK");
        _;
    }

    modifier onlyStakeOwner(uint256 stakeId) {
        require(stakeById[stakeId].owner == msg.sender, "GFlyStaking:NOT_STAKE_OWNER");
        _;
    }

    modifier onlyVestingManager() {
        require(hasRole(VESTING_MANAGER_ROLE, msg.sender), "GFlyStaking:ACCESS_DENIED");
        _;
    }

    modifier onlyGuardian() {
        require(guardian[msg.sender], "GFlyStaking:NOT_GUARDIAN");
        _;
    }

    /**
     * @dev Stake an amount of gFly for a lock period.
     */
    function stake(
        uint256 amount,
        uint16 lock
    ) external override nonReentrant whenNotPaused onlyAvailableLock(lock) returns (uint256) {
        require(amount > 0, "GFlyStaking:CANNOT_STAKE_0");
        gFly.transferFrom(msg.sender, address(this), amount);
        ++currentStakeId;
        stakeById[currentStakeId] = GFlyStake(msg.sender, amount, lock, currentEpoch + lock, 0, currentEpoch, false);
        stakeIdsByAddress[msg.sender].add(currentStakeId);
        unlockableAtEpoch[currentEpoch + lock] += amount;
        emit Staked(msg.sender, currentStakeId, amount, lock, currentEpoch + lock);
        return currentStakeId;
    }

    /**
     * @dev Add gFly to an existing stake
     */
    function addToStake(
        uint256 amount,
        uint256 stakeId
    ) external override nonReentrant whenNotPaused onlyStakeOwner(stakeId) {
        require(amount > 0, "GFlyStaking:CANNOT_STAKE_0");
        gFly.transferFrom(msg.sender, address(this), amount);
        stakeById[stakeId].pendingRewards = claimableById(stakeId);
        stakeById[stakeId].lastProcessEpoch = currentEpoch;
        stakeById[stakeId].amount += amount;
        if (stakeById[stakeId].autoIncreaseLock) {
            autoIncreasedForLocks[stakeById[stakeId].lock] += amount;
        } else {
            unlockableAtEpoch[stakeById[stakeId].unlockEpoch] += amount;
        }
        emit Staked(msg.sender, stakeId, amount, stakeById[stakeId].lock, stakeById[stakeId].unlockEpoch);
    }

    /**
     * @dev Unstake an existing and unlocked gFly stake.
     */
    function unStake(uint256 stakeId) external override nonReentrant whenNotPaused onlyStakeOwner(stakeId) {
        require(
            !stakeById[stakeId].autoIncreaseLock && currentEpoch >= stakeById[stakeId].unlockEpoch,
            "GFlyStaking:STAKE_LOCKED"
        );
        _claim(stakeId);
        gFly.transfer(msg.sender, stakeById[stakeId].amount);
        unlockableAtEpoch[stakeById[stakeId].unlockEpoch] -= stakeById[stakeId].amount;
        emit UnStaked(msg.sender, stakeId, stakeById[stakeId].amount);
        delete stakeById[stakeId];
        stakeIdsByAddress[msg.sender].remove(stakeId);
    }

    /**
     * @dev Unstake all gFly stakes of an account.
     */
    function unStakeAll() external override nonReentrant whenNotPaused {
        uint256 totalAmount = 0;
        uint256[] memory stakeIds = stakeIdsByAddress[msg.sender].values();
        for (uint256 i = 0; i < stakeIds.length; i++) {
            uint256 stakeId = stakeIds[i];
            uint16 unlockEpoch = stakeById[stakeId].unlockEpoch;
            if (!stakeById[stakeId].autoIncreaseLock && currentEpoch >= unlockEpoch) {
                _claim(stakeId);
                uint256 stakeAmount = stakeById[stakeId].amount;
                totalAmount += stakeAmount;
                unlockableAtEpoch[unlockEpoch] -= stakeAmount;
                emit UnStaked(msg.sender, stakeId, stakeAmount);
                delete stakeById[stakeId];
                stakeIdsByAddress[msg.sender].remove(stakeId);
            }
        }
        if (totalAmount > 0) {
            gFly.transfer(msg.sender, totalAmount);
        }
    }

    /**
     * @dev Unstake a batch of gFly stakes of an account.
     */
    function unStakeBatch(uint256[] memory stakeIds) external override nonReentrant whenNotPaused {
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < stakeIds.length; i++) {
            uint256 stakeId = stakeIds[i];
            require(stakeById[stakeId].owner == msg.sender, "GFlyStaking:NOT_STAKE_OWNER");
            uint16 unlockEpoch = stakeById[stakeId].unlockEpoch;
            if (!stakeById[stakeId].autoIncreaseLock && currentEpoch >= unlockEpoch) {
                _claim(stakeId);
                uint256 stakeAmount = stakeById[stakeId].amount;
                totalAmount += stakeAmount;
                unlockableAtEpoch[unlockEpoch] -= stakeAmount;
                emit UnStaked(msg.sender, stakeId, stakeAmount);
                delete stakeById[stakeId];
                stakeIdsByAddress[msg.sender].remove(stakeId);
            }
        }
        if (totalAmount > 0) {
            gFly.transfer(msg.sender, totalAmount);
        }
    }

    /**
     * @dev Function to transfer a stake position for a specified amount to a new owner.
     * This function is created to facilitate the setup of an OTC market for staked positions.
     * The new staking position will follow the emissions schedule of the old position.
     */
    function transferStake(
        uint256 stakeId,
        uint256 amount,
        address newOwner
    ) external whenNotPaused onlyVestingManager {
        require(amount > 0, "GFlyStaking:CANNOT_TRANSFER_0");
        require(stakeById[stakeId].amount >= amount, "GFlyStaking:STAKE_AMOUNT_NOT_SUFFICIENT_FOR_TRANSFER");
        _claim(stakeId);
        ++currentStakeId;
        stakeById[currentStakeId] = GFlyStake(
            newOwner,
            amount,
            stakeById[stakeId].lock,
            stakeById[stakeId].unlockEpoch,
            0,
            currentEpoch,
            stakeById[stakeId].autoIncreaseLock
        );
        stakeIdsByAddress[newOwner].add(currentStakeId);
        stakeById[stakeId].amount -= amount;
        emit StakeTransfered(stakeById[stakeId].owner, stakeId, newOwner, currentStakeId, amount);
        if (stakeById[stakeId].amount == 0) {
            stakeIdsByAddress[stakeById[stakeId].owner].remove(stakeId);
            delete stakeById[stakeId];
        }
    }

    /**
     * @dev Claim the emissions of a gFly stake
     */
    function claim(uint256 stakeId) external override nonReentrant whenNotPaused onlyStakeOwner(stakeId) {
        _claim(stakeId);
    }

    /**
     * @dev Claim all the gFly emissions of the caller
     */
    function claimAll() external override nonReentrant whenNotPaused {
        for (uint256 i = 0; i < stakeIdsByAddress[msg.sender].values().length; i++) {
            _claim(stakeIdsByAddress[msg.sender].at(i));
        }
    }

    /**
     * @dev Claim a batch of gFly emissions
     */
    function claimBatch(uint256[] memory stakeIds) external override nonReentrant whenNotPaused {
        for (uint256 i = 0; i < stakeIds.length; i++) {
            require(stakeById[stakeIds[i]].owner == msg.sender, "GFlyStaking:NOT_STAKE_OWNER");
            _claim(stakeIds[i]);
        }
    }

    /**
     * @dev Claim the gFly emissions of a stake and restake it in 1 go.
     */
    function claimAndRestake(uint256 stakeId) external nonReentrant whenNotPaused onlyStakeOwner(stakeId) {
        _claimAndRestake(stakeId);
    }

    /**
     * @dev Claim all the gFly emissions of the caller and restake them in 1 go.
     */
    function claimAndRestakeAll() external nonReentrant whenNotPaused {
        for (uint256 i = 0; i < stakeIdsByAddress[msg.sender].values().length; i++) {
            _claimAndRestake(stakeIdsByAddress[msg.sender].at(i));
        }
    }

    /**
     * @dev Claim a batch of gFly emissions of the caller and restake them in 1 go.
     */
    function claimAndRestakeBatch(uint256[] memory stakeIds) external nonReentrant whenNotPaused {
        for (uint256 i = 0; i < stakeIds.length; i++) {
            require(stakeById[stakeIds[i]].owner == msg.sender, "GFlyStaking:NOT_STAKE_OWNER");
            _claimAndRestake(stakeIds[i]);
        }
    }

    /**
     * @dev Extend the lock period of a given stake.
     */
    function extendLockPeriod(
        uint256 stakeId,
        uint16 lock
    ) external override whenNotPaused onlyStakeOwner(stakeId) onlyAvailableLock(lock) {
        _extendLockPeriod(stakeId, lock);
    }

    /**
     * @dev Extend the lock period of all stakes of the sender
     */
    function extendLockPeriodOfAllStakes(uint16 lock) external override whenNotPaused onlyAvailableLock(lock) {
        for (uint256 i = 0; i < stakeIdsByAddress[msg.sender].values().length; i++) {
            _extendLockPeriod(stakeIdsByAddress[msg.sender].at(i), lock);
        }
    }

    /**
     * @dev Extend the lock period of a batc of stakes of the sender
     */
    function extendLockPeriodOfBatchStakes(
        uint16 lock,
        uint256[] memory stakeIds
    ) external override whenNotPaused onlyAvailableLock(lock) {
        for (uint256 i = 0; i < stakeIds.length; i++) {
            require(stakeById[stakeIds[i]].owner == msg.sender, "GFlyStaking:NOT_STAKE_OWNER");
            _extendLockPeriod(stakeIds[i], lock);
        }
    }

    /**
     * @dev Enable/disable auto staking increases
     */
    function autoIncreaseLock(uint256 stakeId, bool enable) external override whenNotPaused onlyStakeOwner(stakeId) {
        _autoIncreaseLock(stakeId, enable);
    }

    /**
     * @dev Enable/disable auto staking increases of all stakes of the sender
     */
    function autoIncreaseLockOfAllStakes(bool enable) external override whenNotPaused {
        for (uint256 i = 0; i < stakeIdsByAddress[msg.sender].values().length; i++) {
            if (stakeById[stakeIdsByAddress[msg.sender].at(i)].autoIncreaseLock != enable) {
                _autoIncreaseLock(stakeIdsByAddress[msg.sender].at(i), enable);
            }
        }
    }

    /**
     * @dev Enable/disable auto staking increases of a batch of stakes stakes of the sender
     */
    function autoIncreaseLockOfBatchStakes(bool enable, uint256[] memory stakeIds) external override whenNotPaused {
        for (uint256 i = 0; i < stakeIds.length; i++) {
            require(stakeById[stakeIds[i]].owner == msg.sender, "GFlyStaking:NOT_STAKE_OWNER");
            if (stakeById[stakeIds[i]].autoIncreaseLock != enable) {
                _autoIncreaseLock(stakeIds[i], enable);
            }
        }
    }

    /**
     * @dev Get the claimable gFly emissions of a stake
     */
    function claimableById(uint256 stakeId) public view override returns (uint256 total) {
        total = stakeById[stakeId].pendingRewards;
        for (uint16 i = stakeById[stakeId].lastProcessEpoch; i < currentEpoch; i++) {
            uint256 totalMiningPower = uint256(miningPowerAtEpoch[i]);
            if (totalMiningPower > 0) {
                uint16 lockEpochsRemaining = stakeById[stakeId].autoIncreaseLock
                    ? stakeById[stakeId].lock
                    : (i <= stakeById[stakeId].unlockEpoch ? stakeById[stakeId].unlockEpoch - i : 0);
                uint256 individualMiningPower = uint256(stakeById[stakeId].amount * lockEpochsRemaining) / 365;
                uint256 month = (i / 30) + 1;
                if (month < 37) {
                    total += uint256((emissionsAtMonth[month - 1] * individualMiningPower) / totalMiningPower);
                }
            }
        }
    }

    /**
     * @dev Get the claimable gFly emissions of an account
     */
    function claimableByAddress(address account) external view override returns (uint256 total) {
        for (uint256 i = 0; i < stakeIdsByAddress[account].values().length; i++) {
            total += claimableById(stakeIdsByAddress[account].at(i));
        }
    }

    /**
     * @dev Get the stakeIds of an address
     */
    function getStakesOfAddress(address account) external view override returns (uint256[] memory) {
        return stakeIdsByAddress[account].values();
    }

    /**
     * @dev Get a stake object given the stakeId
     */
    function getStake(uint256 stakeId) external view override returns (GFlyStake memory) {
        return stakeById[stakeId];
    }

    /**
     * @dev Get the total balance staked of an address
     */
    function balanceOf(address account) external view override returns (uint256) {
        uint256 amount;
        for (uint256 i = 0; i < stakeIdsByAddress[account].values().length; i++) {
            amount += stakeById[stakeIdsByAddress[account].at(i)].amount;
        }
        return amount;
    }

    /**
     * @dev Distribute emissions for the current epoch and setting the total mining power with the following formula:
     *      MP = gFLY * (DaysRemaining/365)
     */
    function distributeEmissions() external override whenNotPaused {
        require(hasRole(BATTLEFLY_BOT_ROLE, msg.sender), "GFlyStaking:ACCESS_DENIED");
        require(block.timestamp >= (nextCron - 600) && !cronExecuted[nextCron], "GFlyStaking:NOT_IN_TIME_WINDOW");
        uint256 totalMiningPower;
        for (uint16 i = currentEpoch; i <= currentEpoch + 365; i++) {
            totalMiningPower +=
                ((unlockableAtEpoch[i] + autoIncreasedForLocks[i - currentEpoch]) * uint256(i - currentEpoch)) /
                365;
        }
        miningPowerAtEpoch[currentEpoch] = totalMiningPower;
        currentEpoch++;
        cronExecuted[nextCron] = true;
        nextCron += 86400;
        emit EmissionsDistributed(totalMiningPower, currentEpoch);
    }

    /**
     * @dev Pause the staking contract
     */
    function setPause(bool state) external override onlyGuardian {
        pause = state;
        emit Paused(state);
    }

    /**
     * @dev Correct the pending emissions of a stake
     */
    function setPendingEmissionsOfStake(uint256 stakeId, uint256 pendingRewards) external override {
        require(hasRole(ADMIN_ROLE, msg.sender), "GFlyStaking:ACCESS_DENIED");
        stakeById[stakeId].pendingRewards = pendingRewards;
    }

    /**
     * @dev Set the next cron
     */
    function setNextCron(uint256 nextCron_) external override {
        require(hasRole(ADMIN_ROLE, msg.sender), "GFlyStaking:ACCESS_DENIED");
        nextCron = nextCron_;
    }

    /**
     * @dev Set the guardians
     */
    function setGuardian(address guardian_, bool state) external {
        require(hasRole(ADMIN_ROLE, msg.sender), "GFlyStaking:ACCESS_DENIED");
        guardian[guardian_] = state;
    }

    function _extendLockPeriod(uint256 stakeId, uint16 lock) internal {
        stakeById[stakeId].pendingRewards = claimableById(stakeId);
        stakeById[stakeId].lastProcessEpoch = currentEpoch;
        uint16 newUnlockEpoch = 0;
        if (stakeById[stakeId].autoIncreaseLock) {
            uint16 newLock = stakeById[stakeId].lock + lock > 365 ? 365 : stakeById[stakeId].lock + lock;
            autoIncreasedForLocks[newLock] += stakeById[stakeId].amount;
            autoIncreasedForLocks[stakeById[stakeId].lock] -= stakeById[stakeId].amount;
            stakeById[stakeId].lock = newLock;
        } else {
            uint16 unlockedAt = stakeById[stakeId].unlockEpoch;
            if (unlockedAt < currentEpoch) {
                unlockedAt = currentEpoch;
            }
            newUnlockEpoch = (unlockedAt - currentEpoch) + lock > 365 ? currentEpoch + 365 : unlockedAt + lock;
            unlockableAtEpoch[newUnlockEpoch] += stakeById[stakeId].amount;
            unlockableAtEpoch[stakeById[stakeId].unlockEpoch] -= stakeById[stakeId].amount;
            stakeById[stakeId].unlockEpoch = newUnlockEpoch;
            stakeById[stakeId].lock = newUnlockEpoch - currentEpoch;
        }
        emit LockExtended(msg.sender, stakeId, lock, newUnlockEpoch);
    }

    function _autoIncreaseLock(uint256 stakeId, bool enable) internal {
        require(
            stakeById[stakeId].autoIncreaseLock != enable,
            "GFlyStaking:AUTO_INCREASE_EPOCH_ALREADY_ENABLED_OR_DISABLED"
        );
        stakeById[stakeId].pendingRewards = claimableById(stakeId);
        stakeById[stakeId].lastProcessEpoch = currentEpoch;
        if (enable) {
            uint16 unlockedAt = stakeById[stakeId].unlockEpoch;
            if (unlockedAt < currentEpoch) {
                unlockedAt = currentEpoch;
            }
            unlockableAtEpoch[stakeById[stakeId].unlockEpoch] -= stakeById[stakeId].amount;
            autoIncreasedForLocks[unlockedAt - currentEpoch] += stakeById[stakeId].amount;
            stakeById[stakeId].unlockEpoch = 0;
            stakeById[stakeId].lock = unlockedAt - currentEpoch;
            stakeById[stakeId].autoIncreaseLock = true;
        } else {
            uint16 newUnlockEpoch = currentEpoch + stakeById[stakeId].lock;
            unlockableAtEpoch[newUnlockEpoch] += stakeById[stakeId].amount;
            autoIncreasedForLocks[stakeById[stakeId].lock] -= stakeById[stakeId].amount;
            stakeById[stakeId].unlockEpoch = newUnlockEpoch;
            stakeById[stakeId].autoIncreaseLock = false;
        }
        emit AutoIncreaseLockToggled(msg.sender, stakeId, enable);
    }

    function _claim(uint256 stakeId) internal returns (uint256 claimable) {
        claimable = claimableById(stakeId);
        gFly.mint(stakeById[stakeId].owner, claimable);
        stakeById[stakeId].pendingRewards = 0;
        stakeById[stakeId].lastProcessEpoch = currentEpoch;
        emit Claimed(stakeById[stakeId].owner, stakeId, claimable);
    }

    function _claimAndRestake(uint256 stakeId) internal returns (uint256 claimable) {
        claimable = claimableById(stakeId);
        gFly.mint(address(this), claimable);
        stakeById[stakeId].pendingRewards = 0;
        stakeById[stakeId].lastProcessEpoch = currentEpoch;
        stakeById[stakeId].amount += claimable;
        if (stakeById[stakeId].autoIncreaseLock) {
            autoIncreasedForLocks[stakeById[stakeId].lock] += claimable;
        } else {
            unlockableAtEpoch[stakeById[stakeId].unlockEpoch] += claimable;
        }
        emit ClaimedAndRestaked(stakeById[stakeId].owner, stakeId, claimable);
    }

    /**
     * @dev Set the emissions per day for every month. Equation for total amount of gFly per day:
     *      gFly/day = mx+b (see Charlie's sheet) where:
     *      m = -3.23809353590736
     *      x = month
     *      b = 768.23802833095200
     */
    function _setEmissions() internal {
        for (uint256 i = 0; i < 36; i++) {
            emissionsAtMonth[i] = uint256(-3238093535907360000 * int256(i + 1) + 768238028330952000000);
        }
    }
}

