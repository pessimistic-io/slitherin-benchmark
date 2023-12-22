// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./Initializable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./MerkleProofUpgradeable.sol";
import "./EnumerableSetUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

import "./BattleflyFounderVaultV08.sol";
import "./IBattleflyAtlasStakerV02.sol";
import "./IBattleflyTreasuryFlywheelVault.sol";
import "./IBattlefly.sol";
import "./IAtlasMine.sol";
import "./IBattleflyFounderVault.sol";

contract BattleflyTreasuryFlywheelVault is
    IBattleflyTreasuryFlywheelVault,
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    /**
     * @dev Immutable states
     */
    IERC20Upgradeable public MAGIC;
    IBattleflyAtlasStakerV02 public ATLAS_STAKER;
    IBattleflyFounderVault public FOUNDER_VAULT_V2;
    address public BATTLEFLY_BOT;
    uint256 public V2_VAULT_PERCENTAGE;
    uint256 public TREASURY_PERCENTAGE;
    uint256 public DENOMINATOR;
    IAtlasMine.Lock public TREASURY_LOCK;
    EnumerableSetUpgradeable.UintSet depositIds;
    uint256 public pendingDeposits;
    uint256 public activeRestakeDepositId;
    uint256 public pendingTreasuryAmountToStake;

    /**
     * @dev User stake data
     *      { depositId } => { User stake data }
     */
    mapping(uint256 => UserStake) public userStakes;

    function initialize(
        address _magic,
        address _atlasStaker,
        address _battleflyFounderVaultV2,
        address _battleflyBot
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        require(_magic != address(0), "BattleflyTreasuryFlywheelVault: invalid address");
        require(_atlasStaker != address(0), "BattleflyTreasuryFlywheelVault: invalid address");
        require(_battleflyFounderVaultV2 != address(0), "BattleflyTreasuryFlywheelVault: invalid address");
        require(_battleflyBot != address(0), "BattleflyTreasuryFlywheelVault: invalid address");

        MAGIC = IERC20Upgradeable(_magic);
        ATLAS_STAKER = IBattleflyAtlasStakerV02(_atlasStaker);
        FOUNDER_VAULT_V2 = IBattleflyFounderVault(_battleflyFounderVaultV2);
        BATTLEFLY_BOT = _battleflyBot;

        V2_VAULT_PERCENTAGE = 5000;
        TREASURY_PERCENTAGE = 95000;
        DENOMINATOR = 100000;
        TREASURY_LOCK = IAtlasMine.Lock.twoWeeks;
        MAGIC.approve(address(ATLAS_STAKER), 2**256 - 1);
    }

    /**
     * @dev Deposit funds to AtlasStaker
     */
    function deposit(uint128 _amount) external override nonReentrant onlyOwner returns (uint256 atlasStakerDepositId) {
        MAGIC.safeTransferFrom(msg.sender, address(this), _amount);
        atlasStakerDepositId = _deposit(uint256(_amount));
    }

    /**
     * @dev Withdraw staked funds from AtlasStaker
     */
    function withdraw(uint256[] memory _depositIds, address user)
        public
        override
        nonReentrant
        onlyOwner
        returns (uint256 amount)
    {
        for (uint256 i = 0; i < _depositIds.length; i++) {
            amount += _withdraw(_depositIds[i], user);
        }
    }

    /**
     * @dev Withdraw all from AtlasStaker. This is only possible when the retention period of 14 epochs has passed.
     * The retention period is started when a withdrawal for the stake is requested.
     */
    function withdrawAll(address user) public override nonReentrant onlyOwner returns (uint256 amount) {
        uint256[] memory ids = depositIds.values();
        require(ids.length > 0, "BattleflyTreasuryFlywheelVault: No deposited funds");
        for (uint256 i = 0; i < ids.length; i++) {
            if (ATLAS_STAKER.canWithdraw(ids[i])) {
                amount += _withdraw(ids[i], user);
            }
        }
    }

    /**
     * @dev Request a withdrawal from AtlasStaker. This works with a retention period of 14 epochs.
     * Once the retention period has passed, the stake can be withdrawn.
     */
    function requestWithdrawal(uint256[] memory _depositIds) public override onlyOwner {
        for (uint256 i = 0; i < _depositIds.length; i++) {
            ATLAS_STAKER.requestWithdrawal(_depositIds[i]);
            emit RequestWithdrawal(_depositIds[i]);
        }
    }

    /**
     * @dev Claim emission from AtlasStaker
     */
    function claim(uint256 _depositId, address user) public override nonReentrant onlyOwner returns (uint256 emission) {
        emission = _claim(_depositId, user);
    }

    /**
     * @dev Claim all emissions from AtlasStaker
     */
    function claimAll(address user) external override nonReentrant onlyOwner returns (uint256 amount) {
        uint256[] memory ids = depositIds.values();
        require(ids.length > 0, "BattleflyTreasuryFlywheelVault: No deposited funds");

        for (uint256 i = 0; i < ids.length; i++) {
            amount += _claim(ids[i], user);
        }
    }

    /**
     * @dev Claim all emissions from AtlasStaker, send percentage to V2 Vault and restake.
     */
    function claimAllAndRestake() external override nonReentrant onlyBattleflyBot returns (uint256 amount) {
        uint256[] memory ids = depositIds.values();
        for (uint256 i = 0; i < ids.length; i++) {
            amount += _claim(ids[i], address(this));
        }
        amount = amount + pendingDeposits;
        uint256 v2VaultAmount = (amount * V2_VAULT_PERCENTAGE) / DENOMINATOR;
        uint256 treasuryAmount = (amount * TREASURY_PERCENTAGE) / DENOMINATOR;
        if(v2VaultAmount > 0) {
            MAGIC.approve(address(FOUNDER_VAULT_V2), v2VaultAmount);
            FOUNDER_VAULT_V2.topupTodayEmission(v2VaultAmount);
        }
        pendingTreasuryAmountToStake += treasuryAmount;
        if (activeRestakeDepositId == 0 && pendingTreasuryAmountToStake > 0) {
            activeRestakeDepositId = _deposit(pendingTreasuryAmountToStake);
            pendingTreasuryAmountToStake = 0;
        } else if (activeRestakeDepositId != 0 && canWithdraw(activeRestakeDepositId)) {
            uint256 withdrawn = _withdraw(activeRestakeDepositId, address(this));
            uint256 toDeposit = withdrawn + pendingTreasuryAmountToStake;
            activeRestakeDepositId = _deposit(toDeposit);
            pendingTreasuryAmountToStake = 0;
        } else if (activeRestakeDepositId != 0 && canRequestWithdrawal(activeRestakeDepositId)) {
            ATLAS_STAKER.requestWithdrawal(activeRestakeDepositId);
        }
        pendingDeposits = 0;
    }

    function topupMagic(uint256 amount) public override nonReentrant {
        require(amount > 0);
        MAGIC.safeTransferFrom(msg.sender, address(this), amount);
        pendingDeposits += amount;
        emit TopupMagic(msg.sender, amount);
    }

    // ================ INTERNAL ================

    /**
     * @dev Withdraw a stake from AtlasStaker (Only possible when the retention period has passed)
     */
    function _withdraw(uint256 _depositId, address user) internal returns (uint256 amount) {
        require(ATLAS_STAKER.canWithdraw(_depositId), "BattleflyTreasuryFlywheelVault: stake not yet unlocked");
        amount = ATLAS_STAKER.withdraw(_depositId);
        MAGIC.safeTransfer(user, amount);
        depositIds.remove(_depositId);
        delete userStakes[_depositId];
        emit WithdrawPosition(_depositId, amount);
    }

    /**
     * @dev Claim emission from AtlasStaker
     */
    function _claim(uint256 _depositId, address user) internal returns (uint256 emission) {
        emission = ATLAS_STAKER.claim(_depositId);
        MAGIC.safeTransfer(user, emission);
        emit ClaimEmission(_depositId, emission);
    }

    function _deposit(uint256 _amount) internal returns (uint256 atlasStakerDepositId) {
        atlasStakerDepositId = ATLAS_STAKER.deposit(_amount, TREASURY_LOCK);
        IBattleflyAtlasStakerV02.VaultStake memory vaultStake = ATLAS_STAKER.getVaultStake(atlasStakerDepositId);

        UserStake storage userStake = userStakes[atlasStakerDepositId];
        userStake.amount = _amount;
        userStake.lockAt = vaultStake.lockAt;
        userStake.owner = address(this);
        userStake.lock = TREASURY_LOCK;

        depositIds.add(atlasStakerDepositId);

        emit NewUserStake(atlasStakerDepositId, _amount, vaultStake.unlockAt, address(this), TREASURY_LOCK);
    }

    // ================== VIEW ==================

    /**
     * @dev Get allowed lock periods from AtlasStaker
     */
    function getAllowedLocks() public view override returns (IAtlasMine.Lock[] memory) {
        return ATLAS_STAKER.getAllowedLocks();
    }

    /**
     * @dev Get claimed emission
     */
    function getClaimableEmission(uint256 _depositId) public view override returns (uint256 emission) {
        (emission, ) = ATLAS_STAKER.getClaimableEmission(_depositId);
    }

    /**
     * @dev Check if a vaultStake is eligible for requesting a withdrawal.
     * This is 14 epochs before the end of the initial lock period.
     */
    function canRequestWithdrawal(uint256 _depositId) public view override returns (bool requestable) {
        return ATLAS_STAKER.canRequestWithdrawal(_depositId);
    }

    /**
     * @dev Check if a vaultStake is eligible for a withdrawal
     * This is when the retention period has passed
     */
    function canWithdraw(uint256 _depositId) public view override returns (bool withdrawable) {
        return ATLAS_STAKER.canWithdraw(_depositId);
    }

    /**
     * @dev Check the epoch in which the initial lock period of the vaultStake expires.
     * This is at the end of the lock period
     */
    function initialUnlock(uint256 _depositId) public view override returns (uint64 epoch) {
        return ATLAS_STAKER.getVaultStake(_depositId).unlockAt;
    }

    /**
     * @dev Check the epoch in which the retention period of the vaultStake expires.
     * This is 14 epochs after the withdrawal request has taken place
     */
    function retentionUnlock(uint256 _depositId) public view override returns (uint64 epoch) {
        return ATLAS_STAKER.getVaultStake(_depositId).retentionUnlock;
    }

    /**
     * @dev Get the currently active epoch
     */
    function getCurrentEpoch() public view override returns (uint64 epoch) {
        return ATLAS_STAKER.currentEpoch();
    }

    /**
     * @dev Get the deposit ids
     */
    function getDepositIds() public view override returns (uint256[] memory ids) {
        ids = depositIds.values();
    }

    /**
     * @dev Return the name of the vault
     */
    function getName() public pure override returns (string memory) {
        return "Treasury Flywheel Vault";
    }

    // ================== MODIFIERS ==================

    modifier onlyBattleflyBot() {
        require(msg.sender == BATTLEFLY_BOT, "BattleflyTreasuryFlywheelVault: caller is not a battlefly bot");
        _;
    }

    // ================== EVENTS ==================
    event NewUserStake(uint256 depositId, uint256 amount, uint256 unlockAt, address owner, IAtlasMine.Lock lock);
    event UpdateUserStake(uint256 depositId, uint256 amount, uint256 unlockAt, address owner, IAtlasMine.Lock lock);
    event ClaimEmission(uint256 depositId, uint256 emission);
    event WithdrawPosition(uint256 depositId, uint256 amount);
    event RequestWithdrawal(uint256 depositId);
    event TopupMagic(address sender, uint256 amount);

    event AddedUser(address vault);
    event RemovedUser(address vault);
}

