// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./AccessControlUpgradeable.sol";
import "./Initializable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./EnumerableSetUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./ABDKMath64x64.sol";
import "./IGFlyStaking.sol";

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

contract GFlyLPStaking is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, IGFlyStaking {
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

    modifier onlyStakeOwner(uint256 stakeId) {
        require(stakeById[stakeId].owner == msg.sender, "GFlyLPStaking:NOT_STAKE_OWNER");
        _;
    }

    modifier onlyGuardian() {
        require(guardian[msg.sender], "GFlyLPStaking:NOT_GUARDIAN");
        _;
    }

    /**
     * @dev Stake an amount of gFlyLP for a lock period.
     */
    function stake(
        uint256 amount,
        uint16 lock
    ) external override nonReentrant whenNotPaused onlyAvailableLock(lock) returns (uint256) {
        require(amount > 0, "GFlyLPStaking:CANNOT_STAKE_0");
        gFlyLP.safeTransferFrom(msg.sender, address(this), amount);
        ++currentStakeId;
        stakeById[currentStakeId] = GFlyStake(msg.sender, amount, lock, currentEpoch + lock, 0, currentEpoch);
        stakeIdsByAddress[msg.sender].add(currentStakeId);
        unlockableAtEpoch[currentEpoch + lock] += amount;
        emit Staked(msg.sender, currentStakeId, amount, lock, currentEpoch + lock);
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
        gFlyLP.safeTransferFrom(msg.sender, address(this), amount);
        stakeById[stakeId].pendingRewards = claimableById(stakeId);
        stakeById[stakeId].lastProcessEpoch = currentEpoch;
        stakeById[stakeId].amount += amount;
        unlockableAtEpoch[stakeById[stakeId].unlockEpoch] += amount;
        emit Staked(msg.sender, stakeId, amount, stakeById[stakeId].lock, stakeById[stakeId].unlockEpoch);
    }

    /**
     * @dev Unstake an existing and unlocked gFlyLP stake.
     */
    function unStake(uint256 stakeId) external override nonReentrant whenNotPaused onlyStakeOwner(stakeId) {
        require(currentEpoch >= stakeById[stakeId].unlockEpoch, "GFlyLPStaking:STAKE_LOCKED");
        _claim(stakeId);
        gFlyLP.safeTransfer(msg.sender, stakeById[stakeId].amount);
        unlockableAtEpoch[stakeById[stakeId].unlockEpoch] -= stakeById[stakeId].amount;
        emit UnStaked(msg.sender, stakeId, stakeById[stakeId].amount);
        delete stakeById[stakeId];
        stakeIdsByAddress[msg.sender].remove(stakeId);
    }

    /**
     * @dev Unstake all gFlyLP stakes of an account.
     */
    function unStakeAll() external override nonReentrant whenNotPaused {
        uint256 totalAmount = 0;
        uint256[] memory stakeIds = stakeIdsByAddress[msg.sender].values();
        for (uint256 i = 0; i < stakeIds.length; i++) {
            uint256 stakeId = stakeIds[i];
            uint16 unlockEpoch = stakeById[stakeId].unlockEpoch;
            if (currentEpoch >= unlockEpoch) {
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
            gFlyLP.safeTransfer(msg.sender, totalAmount);
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
     * @dev Get the claimable gFly emissions of a stake
     */
    function claimableById(uint256 stakeId) public view override returns (uint256 total) {
        total = stakeById[stakeId].pendingRewards;
        for (uint16 i = stakeById[stakeId].lastProcessEpoch; i < currentEpoch; i++) {
            uint256 totalMiningPower = uint256(miningPowerAtEpoch[i]);
            uint16 lockEpochsRemaining = i <= stakeById[stakeId].unlockEpoch ? stakeById[stakeId].unlockEpoch - i : 0;
            uint256 individualMiningPower = uint256((stakeById[stakeId].amount * lockEpochsRemaining) / 365);
            uint256 month = (i / 30) + 1;
            if (month < 37) {
                total += uint256((emissionsAtMonth[month - 1] * individualMiningPower) / totalMiningPower);
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
        require(hasRole(BATTLEFLY_BOT_ROLE, msg.sender), "GFlyLPStaking:ACCESS_DENIED");
        require(block.timestamp >= (nextCron - 600) && !cronExecuted[nextCron], "GFlyLPStaking:NOT_IN_TIME_WINDOW");
        uint256 totalMiningPower;
        for (uint16 i = currentEpoch; i <= currentEpoch + 365; i++) {
            totalMiningPower += (unlockableAtEpoch[i] * uint256(i - currentEpoch)) / 365;
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
     * @dev Set the guardians
     */
    function setGuardian(address guardian_, bool state) external {
        require(hasRole(ADMIN_ROLE, msg.sender), "GFlyStaking:ACCESS_DENIED");
        guardian[guardian_] = state;
    }

    function _extendLockPeriod(uint256 stakeId, uint16 lock) internal {
        stakeById[stakeId].pendingRewards = claimableById(stakeId);
        stakeById[stakeId].lastProcessEpoch = currentEpoch;
        uint16 unlockedAt = stakeById[stakeId].unlockEpoch;
        if (stakeById[stakeId].unlockEpoch < currentEpoch) {
            unlockedAt = currentEpoch;
        }
        uint16 newUnlockEpoch = (unlockedAt - currentEpoch) + lock > 365 ? currentEpoch + 365 : unlockedAt + lock;
        unlockableAtEpoch[newUnlockEpoch] += stakeById[stakeId].amount;
        unlockableAtEpoch[stakeById[stakeId].unlockEpoch] -= stakeById[stakeId].amount;
        stakeById[stakeId].unlockEpoch = newUnlockEpoch;
        stakeById[stakeId].lock = newUnlockEpoch - currentEpoch;
        emit LockExtended(msg.sender, stakeId, lock, newUnlockEpoch);
    }

    function _claim(uint256 stakeId) internal returns (uint256 claimable) {
        claimable = claimableById(stakeId);
        gFly.mint(stakeById[stakeId].owner, claimable);
        stakeById[stakeId].pendingRewards = 0;
        stakeById[stakeId].lastProcessEpoch = currentEpoch;
        emit Claimed(stakeById[stakeId].owner, stakeId, claimable);
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

