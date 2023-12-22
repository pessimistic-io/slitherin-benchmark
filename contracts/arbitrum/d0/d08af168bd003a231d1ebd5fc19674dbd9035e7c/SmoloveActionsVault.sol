// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IERC1155Upgradeable.sol";
import "./IERC721Upgradeable.sol";
import "./Initializable.sol";
import "./AddressUpgradeable.sol";
import "./SafeCastUpgradeable.sol";
import "./EnumerableSetUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./AccessControlUpgradeable.sol";

import "./IBattleflyAtlasStakerV02.sol";
import "./ISmoloveActionsVault.sol";
import "./IFlywheelEmissions.sol";
/**
 * @title  SmoloveActionsVault contract
 * @author Archethect
 * @notice This contract contains all functionalities for staking Magic through the Battlefly Flywheel program for Smolove actions (minting, marriage, ...).
 */
contract SmoloveActionsVault is
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    ISmoloveActionsVault
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;
    using SafeCastUpgradeable for uint256;
    using SafeCastUpgradeable for int256;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR");
    bytes32 public constant SMOLOVE_BOT_ROLE = keccak256("SMOLOVE_BOT");

    IERC20Upgradeable public magic;
    IBattleflyAtlasStakerV02 public BattleflyStaker;
    IAtlasMine.Lock public battleflyLock;
    EnumerableSetUpgradeable.UintSet private activeStakes;
    EnumerableSetUpgradeable.UintSet private activeDepositIds;

    uint256 nextStakeId;
    uint256 public activeRestakeDepositId;
    uint256 public pendingDeposits;
    uint256 public pendingAmountToStake;
    uint256 public pendingAmountToWithdraw;
    uint256 public pendingEndOfYearDeposits;
    uint256 public currentDay;
    uint256 public totalStaked;
    address public treasury;

    mapping(uint256 => AtlasStake) public atlasStakes;
    mapping(uint256 => UserStake) public userStakes;
    mapping(address => EnumerableSetUpgradeable.UintSet) private stakesOfOwner;

    // ========== CONTRACT UPGRADE FOR GFLY DYNAMICS ======= //

    IFlywheelEmissions public flywheelEmissions;

    // ============================================ INITIALIZE ==============================================
    function initialize(
        address _admin,
        address _operator,
        address _treasury,
        address _magicAddress,
        address _battleflyStakerAddress,
        address _smolove_bot
    ) external initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();
        require(_admin != address(0), "SMOLOVE_ACTIONS_VAULT:INVALID_ADMIN_ADDRESS");
        require(_operator != address(0), "SMOLOVE_ACTIONS_VAULT:INVALID_OPERATOR_ADDRESS");
        require(_treasury != address(0), "SMOLOVE_ACTIONS_VAULT:INVALID_TREASURY_ADDRESS");
        require(_magicAddress != address(0), "SMOLOVE_ACTIONS_VAULT:INVALID_MAGIC_ADDRESS");
        require(_battleflyStakerAddress != address(0), "SMOLOVE_ACTIONS_VAULT:INVALID_BF_STAKER_ADDRESS");
        require(_smolove_bot != address(0), "SMOLOVE_ACTIONS_VAULT:INVALID_SMOLOVE_BOT_ADDRESS");
        treasury = _treasury;
        magic = IERC20Upgradeable(_magicAddress);
        BattleflyStaker = IBattleflyAtlasStakerV02(_battleflyStakerAddress);
        nextStakeId = 0;
        battleflyLock = IAtlasMine.Lock.twoWeeks;

        _setupRole(ADMIN_ROLE, _admin);
        _setupRole(ADMIN_ROLE, msg.sender);
        _setupRole(OPERATOR_ROLE, _admin);
        _setupRole(OPERATOR_ROLE, _operator);
        _setupRole(SMOLOVE_BOT_ROLE, _smolove_bot);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(OPERATOR_ROLE, ADMIN_ROLE);
        _setRoleAdmin(SMOLOVE_BOT_ROLE, ADMIN_ROLE);
    }

    // ============================================ USER FUNCTIONS ==============================================

    /**
     * @dev stake an amount of Magic in the Atlas Staker
     */
    function stake(address user, uint256 amount) external onlyOperator {
        magic.safeTransferFrom(user, address(this), amount);
        _stake(user, uint256(amount));
    }

    /**
     * @dev Get the total staked amount of a user
     */
    function getStakeAmount(address user) public view returns (uint256) {
        uint256 totalUserStaking = 0;
        for (uint256 i = 0; i < stakesOfOwner[user].length(); i++) {
            uint256 stakeId = stakesOfOwner[user].at(i);
            totalUserStaking += userStakes[stakeId].amount;
        }
        return totalUserStaking;
    }

    /**
     * @dev get the total claimable amount for the treasury
     */
    function getTotalClaimableAmount() external view returns (uint256) {
        uint256 totalClaimable = 0;
        uint256[] memory stakeIds = activeDepositIds.values();
        for (uint256 i = 0; i < stakeIds.length; i++) {
            totalClaimable += _getStakeClaimableAmount(stakeIds[i]);
        }
        if (activeRestakeDepositId != 0) {
            totalClaimable += _getStakeClaimableAmount(activeRestakeDepositId);
        }
        return totalClaimable;
    }

    /**
     * @dev Get the stake objects of a user
     */
    function getUserStakes(address user) external view returns (UserStake[] memory) {
        UserStake[] memory stakes = new UserStake[](stakesOfOwner[user].length());
        for (uint256 i = 0; i < stakesOfOwner[user].length(); i++) {
            uint256 stakeId = stakesOfOwner[user].at(i);
            stakes[i] = userStakes[stakeId];
        }
        return stakes;
    }

    /**
     * @dev Withdraw all withdrawable stakes of the user.
     */
    function withdrawAll() external nonReentrant {
        require(stakesOfOwner[msg.sender].length() > 0, "SMOLOVE_ACTIONS_VAULT:NO_STAKES_TO_WITHDRAW");
        uint256 receiveAmount;
        uint256[] memory stakeIds = stakesOfOwner[msg.sender].values();
        for (uint256 i = 0; i < stakeIds.length; i++) {
            uint256 stakeId = stakeIds[i];
            if (canWithdraw(stakeId)) {
                receiveAmount += _withdrawInternal(stakeId);
            }
        }
        require(receiveAmount > 0, "SMOLOVE_ACTIONS_VAULT:NO_STAKES_TO_WITHDRAW");
        magic.safeTransfer(msg.sender, receiveAmount);
    }

    /**
     * @dev Withdraw a set of stakes from a user. This will fail if one of the stakes is not withdrawable yet (cfr. request withdrawal)
     */
    function withdraw(uint256[] memory stakeIds) external nonReentrant {
        uint256 receiveAmount;
        for (uint256 i = 0; i < stakeIds.length; i++) {
            UserStake storage s = userStakes[stakeIds[i]];
            require(s.owner == msg.sender, "SMOLOVE_ACTIONS_VAULT:ONLY_OWNER_CAN_WITHDRAW");
            receiveAmount += _withdrawInternal(stakeIds[i]);
        }
        require(receiveAmount > 0, "SMOLOVE_ACTIONS_VAULT:NO_STAKES_TO_WITHDRAW");
        magic.safeTransfer(msg.sender, receiveAmount);
    }

    /**
     * @dev Request a withdrawal from the Actions Vault. This works with a retention period of 17 epochs and at least 357 days need to have passed.
     * Once the retention period has passed, the stake can be withdrawn.
     */
    function requestWithdrawal(uint256[] memory stakeIds) public override {
        for (uint256 i = 0; i < stakeIds.length; i++) {
            UserStake storage userStake = userStakes[stakeIds[i]];
            require(userStake.owner == msg.sender, "SMOLOVE_ACTIONS_VAULT:ONLY_OWNER_CAN_REQUEST_WITHDRAWAL");
            require((currentDay - userStake.inclusion) > 356, "SMOLOVE_ACTIONS_VAULT:CAN_NOT_YET_REQUEST_WITHDRAWAL");
            require(userStake.withdrawAt == 0, "SMOLOVE_ACTIONS_VAULT:WITHDRAWAL_ALREADY_REQUESTED");
            userStake.withdrawAt = currentDay + 16;
            pendingAmountToWithdraw += userStake.amount;
            emit RequestWithdrawal(stakeIds[i]);
        }
    }

    /**
     * @dev Check if a vaultStake is eligible for requesting a withdrawal.
     * This is 357 days after the initial stake
     */
    function canRequestWithdrawal(uint256 stakeId) public view override returns (bool requestable) {
        UserStake memory s = userStakes[stakeId];
        if ((s.inclusion > currentDay) || s.withdrawAt > 0) {
            return false;
        }
        return ((currentDay - s.inclusion) > 356);
    }

    /**
     * @dev Check if a vaultStake is eligible for a withdrawal
     * This is when the retention period has passed
     */
    function canWithdraw(uint256 stakeId) public view override returns (bool withdrawable) {
        UserStake memory s = userStakes[stakeId];
        return ((s.withdrawAt > 0) && (currentDay >= s.withdrawAt));
    }

    /**
     * @dev Check the epoch in which the initial lock period of the vaultStake expires.
     * This is at the end of the lock period
     */
    function initialUnlock(uint256 stakeId) public view override returns (uint256 epoch) {
        UserStake memory s = userStakes[stakeId];
        return s.inclusion + 373;
    }

    /**
     * @dev Check the epoch in which the retention period of the vaultStake expires.
     * This is 17 epochs after the withdrawal request has taken place
     */
    function retentionUnlock(uint256 stakeId) public view override returns (uint256 epoch) {
        UserStake memory s = userStakes[stakeId];
        return s.withdrawAt;
    }

    /**
     * @dev Get the currently active epoch
     */
    function getCurrentEpoch() public view override returns (uint256 epoch) {
        return currentDay;
    }

    /**
     * @dev Get the number of active stakes
     */
    function getNumberOfActiveStakes() public view override returns (uint256 amount) {
        return activeStakes.length();
    }

    // ============================================ ADMIN FUNCTIONS ==============================================

    function setBattleflyAtlasStaker(address _atlasStaker) external onlyAdmin {
        require(_atlasStaker != address(0), "SMOLOVE_ACTIONS_VAULT:INVALID_BF_STAKER_ADDRESS");
        BattleflyStaker = IBattleflyAtlasStakerV02(_atlasStaker);
    }

    /**
     * @dev Set the flywheel emissions contract
     */
    function setFlywheelEmissions(address flywheelEmissions_) external onlyAdmin {
        require(flywheelEmissions_ != address(0),"SMOLOVE_ACTIONS_VAULT:INVALID_FLYWHEEL_EMISSIONS_ADDRESS");
        flywheelEmissions = IFlywheelEmissions(flywheelEmissions_);
    }

    /**
     * @dev Claim all emissions from AtlasStaker, and restake
     */
    function claimAllAndRestake(uint256 index,
        uint256 epoch,
        uint256 cumulativeFlywheelAmount,
        uint256 cumulativeHarvesterAmount,
        uint256 flywheelClaimableAtEpoch,
        uint256 harvesterClaimableAtEpoch,
        uint256 individualMiningPower,
        uint256 totalMiningPower,
        bytes32[] calldata merkleProof) external override nonReentrant onlySmoloveBot {
        uint256 amount;
        uint256[] memory ids = activeDepositIds.values();
        if(BattleflyStaker.currentEpoch() <= BattleflyStaker.transitionEpoch()) {
            if (activeRestakeDepositId > 0) {
                amount += _claim(activeRestakeDepositId);
            }
            for (uint256 i = 0; i < ids.length; i++) {
                amount += _claim(ids[i]);
            }
        } else {
            amount += _claimAllFlywheel(
                index,
                epoch,
                cumulativeFlywheelAmount,
                cumulativeHarvesterAmount,
                flywheelClaimableAtEpoch,
                harvesterClaimableAtEpoch,
                individualMiningPower,
                totalMiningPower,
                merkleProof
            );
        }
        if (amount > 0) {
            magic.safeTransfer(treasury, amount);
        }
        pendingAmountToStake += pendingDeposits;

        if (currentDay % 17 == 0 && pendingAmountToStake > 0) {
            uint256 newDepositId = _deposit(pendingAmountToStake);
            atlasStakes[newDepositId] = AtlasStake(newDepositId, pendingAmountToStake, 0, currentDay);
            activeDepositIds.add(newDepositId);
            pendingAmountToStake = 0;
        }

        for (uint256 i = 0; i < ids.length; i++) {
            if ((atlasStakes[ids[i]].withdrawableAt == currentDay) && _canWithdraw(ids[i])) {
                uint256 toDeposit = _withdraw(ids[i]);
                activeDepositIds.remove(ids[i]);
                delete atlasStakes[ids[i]];
                if (activeRestakeDepositId == 0) {
                    activeRestakeDepositId = _deposit(toDeposit);
                } else {
                    pendingEndOfYearDeposits += toDeposit;
                }
                activeDepositIds.remove(ids[i]);
            } else if (((currentDay - atlasStakes[ids[i]].startDay) >= 337) && _canRequestWithdrawal(ids[i])) {
                _requestWithdrawal(ids[i]);
                atlasStakes[ids[i]].withdrawableAt = currentDay + 16;
            }
        }

        if (activeRestakeDepositId != 0) {
            if (_canWithdraw(activeRestakeDepositId)) {
                uint256 toDeposit = _withdraw(activeRestakeDepositId);
                toDeposit = toDeposit + pendingEndOfYearDeposits - pendingAmountToWithdraw;
                if (toDeposit > 0) {
                    activeRestakeDepositId = _deposit(toDeposit);
                } else {
                    activeRestakeDepositId = 0;
                }
                pendingEndOfYearDeposits = 0;
                pendingAmountToWithdraw = 0;
            } else if (_canRequestWithdrawal(activeRestakeDepositId)) {
                _requestWithdrawal(activeRestakeDepositId);
            }
        }

        pendingDeposits = 0;
        currentDay++;
        emit ClaimAndRestake(amount);
    }

    // ============================================ INTERNAL FUNCTIONS ==============================================

    function _withdrawInternal(uint256 stakeId) internal returns (uint256) {
        UserStake storage s = userStakes[stakeId];
        uint256 returnAmount;
        require(currentDay >= s.withdrawAt, "SMOLOVE_ACTIONS_VAULT:CANNOT_WITHRAW_BEFORE_RETENTION_PERIOD_HAS_PASSED");
        totalStaked -= s.amount;
        returnAmount = s.amount;
        stakesOfOwner[msg.sender].remove(stakeId);
        activeStakes.remove(stakeId);
        delete userStakes[stakeId];
        emit Withdraw(msg.sender, stakeId, s.amount);
        return returnAmount;
    }

    function _getStakeClaimableAmount(uint256 stakeId) internal view returns (uint256) {
        (uint256 claimAmount, ) = BattleflyStaker.getClaimableEmission(stakeId);
        return claimAmount;
    }

    function _claim(uint256 stakeId) internal returns (uint256) {
        return BattleflyStaker.claim(stakeId);
    }

    function _deposit(uint256 amount) internal returns (uint256) {
        magic.safeApprove(address(BattleflyStaker), amount);
        return BattleflyStaker.deposit(amount, battleflyLock);
    }

    function _withdraw(uint256 depositId) internal returns (uint256) {
        return BattleflyStaker.withdraw(depositId);
    }

    function _canWithdraw(uint256 depositId) internal view returns (bool) {
        return BattleflyStaker.canWithdraw(depositId);
    }

    function _canRequestWithdrawal(uint256 depositId) internal view returns (bool) {
        return BattleflyStaker.canRequestWithdrawal(depositId);
    }

    function _requestWithdrawal(uint256 depositId) internal {
        BattleflyStaker.requestWithdrawal(depositId);
    }

    function _stake(address user, uint256 amount) internal returns (uint256) {
        require(amount > 0, "SMOLOVE_ACTIONS_VAULT:AMOUNT_MUST_BE_GREATER_THAN_0");
        pendingAmountToStake += amount;
        UserStake storage s = userStakes[nextStakeId];
        s.amount = amount;
        s.inclusion = (currentDay + ((17 - (currentDay % 17)) % 17));
        s.owner = user;
        s.id = nextStakeId;
        stakesOfOwner[user].add(nextStakeId);
        activeStakes.add(nextStakeId);
        emit Stake(user, nextStakeId, amount, s.inclusion);
        nextStakeId++;
        totalStaked += amount;
        return nextStakeId - 1;
    }

    function _claimAllFlywheel(uint256 index,
        uint256 epoch,
        uint256 cumulativeFlywheelAmount,
        uint256 cumulativeHarvesterAmount,
        uint256 flywheelClaimableAtEpoch,
        uint256 harvesterClaimableAtEpoch,
        uint256 individualMiningPower,
        uint256 totalMiningPower,
        bytes32[] calldata merkleProof) internal returns (uint256 amount) {
        uint256 beforeClaim = magic.balanceOf(address(this));
        flywheelEmissions.claim(
            index,
            epoch,
            cumulativeFlywheelAmount,
            cumulativeHarvesterAmount,
            flywheelClaimableAtEpoch,
            harvesterClaimableAtEpoch,
                individualMiningPower,
                totalMiningPower,
            merkleProof
        );
        uint256 afterClaim = magic.balanceOf(address(this));
        amount = afterClaim - beforeClaim;
    }

    // ============================================ MODIFIERS ==============================================

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "SMOLOVE_ACTIONS_VAULT:ACCESS_DENIED");
        _;
    }

    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, msg.sender), "SMOLOVE_ACTIONS_VAULT:ACCESS_DENIED");
        _;
    }

    modifier onlySmoloveBot() {
        require(hasRole(SMOLOVE_BOT_ROLE, msg.sender), "SMOLOVE_ACTIONS_VAULT:ACCESS_DENIED");
        _;
    }
}

