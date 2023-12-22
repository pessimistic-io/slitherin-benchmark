// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./AccessControlUpgradeable.sol";
import "./Initializable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./EnumerableSetUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./ABDKMath64x64.sol";
import "./IGFlyLPStaking.sol";

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

contract GFlyLPStaking is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, IGFlyLPStaking {
    using ABDKMath64x64 for uint256;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @dev The identifier of the role which maintains other roles.
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");
    /// @dev The identifier of the role which allows accounts to run cron jobs.
    bytes32 public constant BATTLEFLY_BOT_ROLE = keccak256("BATTLEFLY_BOT");

    int128 public COEFFICIENT_A;
    int128 public COEFFICIENT_B;
    int128 public COEFFICIENT_C;

    bool public pause;
    uint16 public currentEpoch;
    uint256 public currentStakeId;
    uint256 public nextCron;
    uint256[36] public emissionsAtMonth;
    mapping(uint256 => bool) public cronExecuted;

    IGFly public gFly;
    IERC20Upgradeable public gFlyLP;

    mapping(uint16 => uint256) public unlockableAtEpoch;
    mapping(uint16 => uint256) public miningPowerAtEpoch;
    mapping(uint256 => GFlyStake) public stakeById;
    mapping(address => EnumerableSetUpgradeable.UintSet) private stakeIdsByAddress;

    // Extension for non-multisig guardians
    mapping(address => bool) public guardian;

    // Extension for lock auto-increasing
    mapping(uint16 => uint256) public autoIncreasedForLocks;

    //extension for support of Trident DAO pairs
    IERC20Upgradeable public gFlyLPTridentUSDC;
    IERC20Upgradeable public gFlyLPTridentPSI;
    mapping(uint16 => mapping(uint16 => uint256)) public unlockableAtEpochForAdditionalPairs;
    mapping(uint16 => mapping(uint16 => uint256)) public autoIncreasedForLocksForAdditionalPairs;
    mapping(uint16 => uint256) public miningPowerCoefficientsInWei;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address gFly_, address dao, address battleflyBot, uint256 nextCron_) external initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();

        require(gFly_ != address(0), "GFlyLPStaking:INVALID_ADDRESS");
        require(dao != address(0), "GFlyLPStaking:INVALID_ADDRESS");
        require(battleflyBot != address(0), "GFlyLPStaking:INVALID_ADDRESS");

        _setupRole(ADMIN_ROLE, dao);
        _setupRole(ADMIN_ROLE, msg.sender); // This will be surrendered after deployment
        _setupRole(BATTLEFLY_BOT_ROLE, battleflyBot);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(BATTLEFLY_BOT_ROLE, ADMIN_ROLE);

        gFly = IGFly(gFly_);

        currentEpoch = 1;
        pause = true;
        nextCron = nextCron_;
        COEFFICIENT_A = 13019407595946985322971; //  705.7835 in signed 64.64-bit fixed point number.
        COEFFICIENT_B = 55340232221128654; //  0.003 in signed 64.64-bit fixed point number.
        COEFFICIENT_C = 5771986220663718700; //  0.3129 in signed 64.64-bit fixed point number.

        _setEmissions();
    }

    modifier whenNotPaused() {
        require(!pause, "GFlyLPStaking:PAUSED");
        _;
    }

    modifier onlyAvailableLock(uint16 lock) {
        require(lock >= 1 && lock <= 365, "GFlyLPStaking:UNALLOWED_LOCK");
        _;
    }

    // 0 = gFLY/Magic, 1 = gFLY/USDC, 2 = gFLY/PSI
    modifier onlyAvailableStakeType(uint16 stakeType) {
        require(stakeType >= 0 && stakeType <= 2, "GFlyLPStaking:UNALLOWED_STAKE_TYPE");
        _;
    }

    modifier onlyStakeOwner(uint256 stakeId) {
        require(stakeById[stakeId].owner == msg.sender, "GFlyLPStaking:NOT_STAKE_OWNER");
        _;
    }

    modifier onlyGuardian() {
        require(guardian[msg.sender], "GFlyLPStaking:NOT_GUARDIAN");
        _;
    }

    /**
     * @dev Stake an amount of gFlyLP for a lock period and for a specific type.
     * 0 = gFLY/Magic, 1 = gFLY/USDC, 2 = gFLY/PSI
     */
    function stake(
        uint256 amount,
        uint16 lock,
        uint16 stakeType
    ) external override nonReentrant whenNotPaused onlyAvailableLock(lock) returns (uint256) {
        require(amount > 0, "GFlyLPStaking:CANNOT_STAKE_0");
        _transferStakeOfTypeToContract(msg.sender, amount, stakeType);
        ++currentStakeId;
        stakeById[currentStakeId] = GFlyStake(
            msg.sender,
            amount,
            lock,
            currentEpoch + lock,
            0,
            currentEpoch,
            false,
            stakeType
        );
        stakeIdsByAddress[msg.sender].add(currentStakeId);
        if (stakeType == 0) {
            unlockableAtEpoch[currentEpoch + lock] += amount;
        } else {
            unlockableAtEpochForAdditionalPairs[stakeType][currentEpoch + lock] += amount;
        }
        emit Staked(msg.sender, currentStakeId, amount, lock, currentEpoch + lock, stakeType);
        return currentStakeId;
    }

    /**
     * @dev Add gFlyLP to an existing stake
     */
    function addToStake(
        uint256 amount,
        uint256 stakeId
    ) external override nonReentrant whenNotPaused onlyStakeOwner(stakeId) {
        require(amount > 0, "GFlyLPStaking:CANNOT_STAKE_0");
        _transferStakeOfTypeToContract(msg.sender, amount, stakeById[stakeId].stakeType);
        stakeById[stakeId].pendingRewards = claimableById(stakeId);
        stakeById[stakeId].lastProcessEpoch = currentEpoch;
        stakeById[stakeId].amount += amount;
        if (stakeById[stakeId].autoIncreaseLock) {
            if (stakeById[stakeId].stakeType == 0) {
                autoIncreasedForLocks[stakeById[stakeId].lock] += amount;
            } else {
                autoIncreasedForLocksForAdditionalPairs[stakeById[stakeId].stakeType][
                    stakeById[stakeId].lock
                ] += amount;
            }
        } else {
            if (stakeById[stakeId].stakeType == 0) {
                unlockableAtEpoch[stakeById[stakeId].unlockEpoch] += amount;
            } else {
                unlockableAtEpochForAdditionalPairs[stakeById[stakeId].stakeType][
                    stakeById[stakeId].unlockEpoch
                ] += amount;
            }
        }
        emit Staked(
            msg.sender,
            stakeId,
            amount,
            stakeById[stakeId].lock,
            stakeById[stakeId].unlockEpoch,
            stakeById[stakeId].stakeType
        );
    }

    /**
     * @dev Unstake an existing and unlocked gFlyLP stake.
     */
    function unStake(uint256 stakeId) external override nonReentrant whenNotPaused onlyStakeOwner(stakeId) {
        require(
            !stakeById[stakeId].autoIncreaseLock && currentEpoch >= stakeById[stakeId].unlockEpoch,
            "GFlyLPStaking:STAKE_LOCKED"
        );
        _claim(stakeId);
        _transferStakeOfTypeFromContract(msg.sender, stakeById[stakeId].amount, stakeById[stakeId].stakeType);
        if (stakeById[stakeId].stakeType == 0) {
            unlockableAtEpoch[stakeById[stakeId].unlockEpoch] -= stakeById[stakeId].amount;
        } else {
            unlockableAtEpochForAdditionalPairs[stakeById[stakeId].stakeType][
                stakeById[stakeId].unlockEpoch
            ] += stakeById[stakeId].amount;
        }
        emit UnStaked(msg.sender, stakeId, stakeById[stakeId].amount, stakeById[stakeId].stakeType);
        delete stakeById[stakeId];
        stakeIdsByAddress[msg.sender].remove(stakeId);
    }

    /**
     * @dev Unstake all gFlyLP stakes of an account.
     */
    function unStakeAll() external override nonReentrant whenNotPaused {
        uint256[] memory totalAmounts = new uint256[](3);
        uint256[] memory stakeIds = stakeIdsByAddress[msg.sender].values();
        for (uint256 i = 0; i < stakeIds.length; i++) {
            uint256 stakeId = stakeIds[i];
            uint16 unlockEpoch = stakeById[stakeId].unlockEpoch;
            if (!stakeById[stakeId].autoIncreaseLock && currentEpoch >= unlockEpoch) {
                _claim(stakeId);
                uint16 stakeType = stakeById[stakeId].stakeType;
                uint256 stakeAmount = stakeById[stakeId].amount;
                if (stakeType == 0) {
                    totalAmounts[0] += stakeAmount;
                    unlockableAtEpoch[unlockEpoch] -= stakeAmount;
                } else {
                    if (stakeType == 1) {
                        totalAmounts[1] += stakeAmount;
                    } else {
                        totalAmounts[2] += stakeAmount;
                    }
                    unlockableAtEpochForAdditionalPairs[stakeType][unlockEpoch] -= stakeAmount;
                }
                emit UnStaked(msg.sender, stakeId, stakeAmount, stakeType);
                delete stakeById[stakeId];
                stakeIdsByAddress[msg.sender].remove(stakeId);
            }
        }
        for (uint16 i = 0; i < totalAmounts.length; i++) {
            if (totalAmounts[i] > 0) {
                _transferStakeOfTypeFromContract(msg.sender, totalAmounts[i], i);
            }
        }
    }

    /**
     * @dev Unstake a batch of gFly stakes of an account.
     */
    function unStakeBatch(uint256[] memory stakeIds) external override nonReentrant whenNotPaused {
        uint256[] memory totalAmounts = new uint256[](3);
        for (uint256 i = 0; i < stakeIds.length; i++) {
            uint256 stakeId = stakeIds[i];
            require(stakeById[stakeId].owner == msg.sender, "GFlyLPStaking:NOT_STAKE_OWNER");
            uint16 unlockEpoch = stakeById[stakeId].unlockEpoch;
            if (!stakeById[stakeId].autoIncreaseLock && currentEpoch >= unlockEpoch) {
                _claim(stakeId);
                uint16 stakeType = stakeById[stakeId].stakeType;
                uint256 stakeAmount = stakeById[stakeId].amount;
                if (stakeType == 0) {
                    totalAmounts[0] += stakeAmount;
                    unlockableAtEpoch[unlockEpoch] -= stakeAmount;
                } else {
                    if (stakeType == 1) {
                        totalAmounts[1] += stakeAmount;
                    } else {
                        totalAmounts[2] += stakeAmount;
                    }
                    unlockableAtEpochForAdditionalPairs[stakeType][unlockEpoch] -= stakeAmount;
                }
                emit UnStaked(msg.sender, stakeId, stakeAmount, stakeType);
                delete stakeById[stakeId];
                stakeIdsByAddress[msg.sender].remove(stakeId);
            }
        }
        for (uint16 i = 0; i < totalAmounts.length; i++) {
            if (totalAmounts[i] > 0) {
                _transferStakeOfTypeFromContract(msg.sender, totalAmounts[i], i);
            }
        }
    }

    /**
     * @dev Claim the emissions of a gFlyLP stake
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
            require(stakeById[stakeIds[i]].owner == msg.sender, "GFlyLPStaking:NOT_STAKE_OWNER");
            _claim(stakeIds[i]);
        }
    }

    /**
     * @dev Extend the lock period of a give stake.
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
     * @dev Extend the lock period of a batch of stakes of the sender
     */
    function extendLockPeriodOfBatchStakes(
        uint16 lock,
        uint256[] memory stakeIds
    ) external override whenNotPaused onlyAvailableLock(lock) {
        for (uint256 i = 0; i < stakeIds.length; i++) {
            require(stakeById[stakeIds[i]].owner == msg.sender, "GFlyLPStaking:NOT_STAKE_OWNER");
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
            require(stakeById[stakeIds[i]].owner == msg.sender, "GFlyLPStaking:NOT_STAKE_OWNER");
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
                uint256 individualMiningPower = uint256(
                    ((stakeById[stakeId].amount *
                        miningPowerCoefficientsInWei[stakeById[stakeId].stakeType] *
                        lockEpochsRemaining) / 1e18) / 365
                );
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
     * @dev Get the total balance staked of an address per stakeType
     */
    function balanceOf(address account, uint16 stakeType) external view override returns (uint256) {
        uint256 amount;
        for (uint256 i = 0; i < stakeIdsByAddress[account].values().length; i++) {
            if (stakeById[stakeIdsByAddress[account].at(i)].stakeType == stakeType) {
                amount += stakeById[stakeIdsByAddress[account].at(i)].amount;
            }
        }
        return amount;
    }

    /**
     * @dev Distribute emissions for the current epoch and setting the total mining power with the following formula:
     *      MP = gFLY * (DaysRemaining/365)
     */
    function distributeEmissions() external override whenNotPaused {
        require(hasRole(BATTLEFLY_BOT_ROLE, msg.sender), "GFlyLPStaking:ACCESS_DENIED");
        require(block.timestamp >= (nextCron - 600) && !cronExecuted[nextCron], "GFlyLPStaking:NOT_IN_TIME_WINDOW");
        uint256 totalMiningPower;
        for (uint16 i = currentEpoch; i <= currentEpoch + 365; i++) {
            totalMiningPower +=
                (((((unlockableAtEpoch[i] + autoIncreasedForLocks[i - currentEpoch]) *
                    miningPowerCoefficientsInWei[0]) / 1e18) * uint256(i - currentEpoch)) / 365) +
                (((((unlockableAtEpochForAdditionalPairs[1][i] +
                    autoIncreasedForLocksForAdditionalPairs[1][i - currentEpoch]) * miningPowerCoefficientsInWei[1]) /
                    1e18) * uint256(i - currentEpoch)) / 365) +
                (((((unlockableAtEpochForAdditionalPairs[2][i] +
                    autoIncreasedForLocksForAdditionalPairs[2][i - currentEpoch]) * miningPowerCoefficientsInWei[2]) /
                    1e18) * uint256(i - currentEpoch)) / 365);
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
     * @dev Revert the previous emission distribution
     */
    function revertEmissionDistribution() external override {
        require(hasRole(ADMIN_ROLE, msg.sender), "GFlyStaking:ACCESS_DENIED");
        currentEpoch--;
        nextCron -= 86400;
        cronExecuted[nextCron] = false;
    }

    /**
     * @dev Set the next cron
     */
    function setNextCron(uint256 nextCron_) external override {
        require(hasRole(ADMIN_ROLE, msg.sender), "GFlyStaking:ACCESS_DENIED");
        nextCron = nextCron_;
    }

    /**
     * @dev Correct the pending emissions of a stake
     */
    function setPendingEmissionsOfStake(uint256 stakeId, uint256 pendingRewards) external override {
        require(hasRole(ADMIN_ROLE, msg.sender), "GFlyLPStaking:ACCESS_DENIED");
        stakeById[stakeId].pendingRewards = pendingRewards;
    }

    /**
     * @dev Set the GFlyLP pair
     */
    function setGFlyLP(address gFlyLP_) external {
        require(hasRole(ADMIN_ROLE, msg.sender), "GFlyStaking:ACCESS_DENIED");
        require(gFlyLP_ != address(0), "GFlyLPStaking:INVALID_ADDRESS");
        gFlyLP = IERC20Upgradeable(gFlyLP_);
    }

    /**
     * @dev Set the GFlyLPTridentUSDC pair
     */
    function setGFlyLPTridentUSDC(address gFlyLPTridentUSDC_) external {
        require(hasRole(ADMIN_ROLE, msg.sender), "GFlyStaking:ACCESS_DENIED");
        require(gFlyLPTridentUSDC_ != address(0), "GFlyLPStaking:INVALID_ADDRESS");
        gFlyLPTridentUSDC = IERC20Upgradeable(gFlyLPTridentUSDC_);
    }

    /**
     * @dev Set the GFlyLPTridentPSI pair
     */
    function setGFlyLPTridentPSI(address gFlyLPTridentPSI_) external {
        require(hasRole(ADMIN_ROLE, msg.sender), "GFlyStaking:ACCESS_DENIED");
        require(gFlyLPTridentPSI_ != address(0), "GFlyLPStaking:INVALID_ADDRESS");
        gFlyLPTridentPSI = IERC20Upgradeable(gFlyLPTridentPSI_);
    }

    function setMiningPowerCoefficientInWeiForStakeType(uint16 stakeType, uint256 coefficient) external {
        require(hasRole(ADMIN_ROLE, msg.sender), "GFlyStaking:ACCESS_DENIED");
        miningPowerCoefficientsInWei[stakeType] = coefficient;
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
            if (stakeById[stakeId].stakeType == 0) {
                autoIncreasedForLocks[newLock] += stakeById[stakeId].amount;
                autoIncreasedForLocks[stakeById[stakeId].lock] -= stakeById[stakeId].amount;
            } else {
                autoIncreasedForLocksForAdditionalPairs[stakeById[stakeId].stakeType][newLock] += stakeById[stakeId]
                    .amount;
                autoIncreasedForLocksForAdditionalPairs[stakeById[stakeId].stakeType][
                    stakeById[stakeId].lock
                ] -= stakeById[stakeId].amount;
            }
            stakeById[stakeId].lock = newLock;
        } else {
            uint16 unlockedAt = stakeById[stakeId].unlockEpoch;
            if (unlockedAt < currentEpoch) {
                unlockedAt = currentEpoch;
            }
            newUnlockEpoch = (unlockedAt - currentEpoch) + lock > 365 ? currentEpoch + 365 : unlockedAt + lock;
            if (stakeById[stakeId].stakeType == 0) {
                unlockableAtEpoch[newUnlockEpoch] += stakeById[stakeId].amount;
                unlockableAtEpoch[stakeById[stakeId].unlockEpoch] -= stakeById[stakeId].amount;
            } else {
                unlockableAtEpochForAdditionalPairs[stakeById[stakeId].stakeType][newUnlockEpoch] += stakeById[stakeId]
                    .amount;
                unlockableAtEpochForAdditionalPairs[stakeById[stakeId].stakeType][
                    stakeById[stakeId].unlockEpoch
                ] -= stakeById[stakeId].amount;
            }
            stakeById[stakeId].unlockEpoch = newUnlockEpoch;
            stakeById[stakeId].lock = newUnlockEpoch - currentEpoch;
        }
        emit LockExtended(msg.sender, stakeId, lock, newUnlockEpoch);
    }

    function _autoIncreaseLock(uint256 stakeId, bool enable) internal {
        require(
            stakeById[stakeId].autoIncreaseLock != enable,
            "GFlyLPStaking:AUTO_INCREASE_EPOCH_ALREADY_ENABLED_OR_DISABLED"
        );
        stakeById[stakeId].pendingRewards = claimableById(stakeId);
        stakeById[stakeId].lastProcessEpoch = currentEpoch;
        if (enable) {
            uint16 unlockedAt = stakeById[stakeId].unlockEpoch;
            if (unlockedAt < currentEpoch) {
                unlockedAt = currentEpoch;
            }
            if (stakeById[stakeId].stakeType == 0) {
                unlockableAtEpoch[stakeById[stakeId].unlockEpoch] -= stakeById[stakeId].amount;
                autoIncreasedForLocks[unlockedAt - currentEpoch] += stakeById[stakeId].amount;
            } else {
                unlockableAtEpochForAdditionalPairs[stakeById[stakeId].stakeType][
                    stakeById[stakeId].unlockEpoch
                ] -= stakeById[stakeId].amount;
                autoIncreasedForLocksForAdditionalPairs[stakeById[stakeId].stakeType][
                    unlockedAt - currentEpoch
                ] += stakeById[stakeId].amount;
            }
            stakeById[stakeId].unlockEpoch = 0;
            stakeById[stakeId].lock = unlockedAt - currentEpoch;
            stakeById[stakeId].autoIncreaseLock = true;
        } else {
            uint16 newUnlockEpoch = currentEpoch + stakeById[stakeId].lock;
            if (stakeById[stakeId].stakeType == 0) {
                unlockableAtEpoch[newUnlockEpoch] += stakeById[stakeId].amount;
                autoIncreasedForLocks[stakeById[stakeId].lock] -= stakeById[stakeId].amount;
            } else {
                unlockableAtEpochForAdditionalPairs[stakeById[stakeId].stakeType][newUnlockEpoch] += stakeById[stakeId]
                    .amount;
                autoIncreasedForLocksForAdditionalPairs[stakeById[stakeId].stakeType][
                    stakeById[stakeId].lock
                ] -= stakeById[stakeId].amount;
            }
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

    function _transferStakeOfTypeToContract(
        address account,
        uint256 amount,
        uint16 stakeType
    ) internal onlyAvailableStakeType(stakeType) {
        if (stakeType == 0) {
            gFlyLP.safeTransferFrom(account, address(this), amount);
        } else if (stakeType == 1) {
            gFlyLPTridentUSDC.safeTransferFrom(account, address(this), amount);
        } else {
            gFlyLPTridentPSI.safeTransferFrom(account, address(this), amount);
        }
    }

    function _transferStakeOfTypeFromContract(
        address account,
        uint256 amount,
        uint16 stakeType
    ) internal onlyAvailableStakeType(stakeType) {
        if (stakeType == 0) {
            gFlyLP.safeTransfer(account, amount);
        } else if (stakeType == 1) {
            gFlyLPTridentUSDC.safeTransfer(account, amount);
        } else {
            gFlyLPTridentPSI.safeTransfer(account, amount);
        }
    }

    /**
     * @dev Set the emissions per day for every month. Equation for total amount of gFly per day:
     *      gFLY/day = a*(1-((b*e^(c*x))/((b*e^(c*x))+1))) (see Charlie's sheet) where:
     *      a = 705.926245973992
     *      b = 0.003
     *      c = 0.312962
     */
    function _setEmissions() internal {
        for (uint256 i = 0; i < 36; i++) {
            int128 curve = ABDKMath64x64.mul(
                COEFFICIENT_B,
                ABDKMath64x64.exp(ABDKMath64x64.mul(COEFFICIENT_C, ABDKMath64x64.fromUInt(i + 1)))
            );
            emissionsAtMonth[i] = uint256(
                ABDKMath64x64.mulu(
                    ABDKMath64x64.mul(
                        COEFFICIENT_A,
                        ABDKMath64x64.sub(
                            ABDKMath64x64.fromUInt(1),
                            ABDKMath64x64.div(curve, ABDKMath64x64.add(curve, ABDKMath64x64.fromUInt(1)))
                        )
                    ),
                    1e18
                )
            );
        }
    }
}

