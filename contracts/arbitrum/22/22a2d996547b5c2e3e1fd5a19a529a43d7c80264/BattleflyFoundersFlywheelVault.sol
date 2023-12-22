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
import "./IBattleflyFoundersFlywheelVault.sol";
import "./IBattlefly.sol";
import "./IAtlasMine.sol";
import "./IBattleflyFounderVault.sol";

contract BattleflyFoundersFlywheelVault is
    IBattleflyFoundersFlywheelVault,
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
    IBattleflyFounderVault public FOUNDER_VAULT_V1;
    IBattleflyFounderVault public FOUNDER_VAULT_V2;
    uint256 public override STAKING_LIMIT_V1;
    uint256 public override STAKING_LIMIT_V2;

    /**
     * @dev User stake data
     *      { depositId } => { User stake data }
     */
    mapping(uint256 => UserStake) public userStakes;

    /**
     * @dev User's depositIds
     *      { user } => { depositIds }
     */
    mapping(address => EnumerableSetUpgradeable.UintSet) private depositIdByUser;

    /**
     * @dev Whitelisted users
     *      { user } => { is whitelisted }
     */
    mapping(address => bool) public whitelistedUsers;

    function initialize(
        address _magic,
        address _atlasStaker,
        address _battleflyFounderVaultV1,
        address _battleflyFounderVaultV2
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        require(_magic != address(0), "BattleflyFlywheelVault: invalid address");
        require(_atlasStaker != address(0), "BattleflyFlywheelVault: invalid address");
        require(_battleflyFounderVaultV1 != address(0), "BattleflyFlywheelVault: invalid address");
        require(_battleflyFounderVaultV2 != address(0), "BattleflyFlywheelVault: invalid address");

        MAGIC = IERC20Upgradeable(_magic);
        ATLAS_STAKER = IBattleflyAtlasStakerV02(_atlasStaker);
        FOUNDER_VAULT_V1 = IBattleflyFounderVault(_battleflyFounderVaultV1);
        FOUNDER_VAULT_V2 = IBattleflyFounderVault(_battleflyFounderVaultV2);

        STAKING_LIMIT_V1 = 20000e18;
        STAKING_LIMIT_V2 = 10000e18;
    }

    /**
     * @dev Deposit funds to AtlasStaker
     */
    function deposit(uint128 _amount, IAtlasMine.Lock _lock)
        external
        override
        nonReentrant
        onlyMembers
        returns (uint256 atlasStakerDepositId)
    {
        if (!whitelistedUsers[msg.sender]) {
            require(
                remainingStakeableAmount(msg.sender) >= _amount,
                "BattleflyFlywheelVault: amount exceeds stakeable amount"
            );
        }
        MAGIC.safeTransferFrom(msg.sender, address(this), _amount);
        MAGIC.safeApprove(address(ATLAS_STAKER), _amount);

        atlasStakerDepositId = ATLAS_STAKER.deposit(uint256(_amount), _lock);
        IBattleflyAtlasStakerV02.VaultStake memory vaultStake = ATLAS_STAKER.getVaultStake(atlasStakerDepositId);

        UserStake storage userStake = userStakes[atlasStakerDepositId];
        userStake.amount = _amount;
        userStake.lockAt = vaultStake.lockAt;
        userStake.owner = msg.sender;
        userStake.lock = _lock;

        depositIdByUser[msg.sender].add(atlasStakerDepositId);

        emit NewUserStake(atlasStakerDepositId, _amount, vaultStake.unlockAt, msg.sender, _lock);
    }

    /**
     * @dev Withdraw staked funds from AtlasStaker
     */
    function withdraw(uint256[] memory _depositIds) public override nonReentrant returns (uint256 amount) {
        for (uint256 i = 0; i < _depositIds.length; i++) {
            amount += _withdraw(_depositIds[i]);
        }
    }

    /**
     * @dev Withdraw all from AtlasStaker. This is only possible when the retention period of 14 epochs has passed.
     * The retention period is started when a withdrawal for the stake is requested.
     */
    function withdrawAll() public override nonReentrant returns (uint256 amount) {
        uint256[] memory depositIds = depositIdByUser[msg.sender].values();
        require(depositIds.length > 0, "BattleflyFlywheelVault: No deposited funds");
        for (uint256 i = 0; i < depositIds.length; i++) {
            if (ATLAS_STAKER.canWithdraw(depositIds[i])) {
                amount += _withdraw(depositIds[i]);
            }
        }
    }

    /**
     * @dev Request a withdrawal from AtlasStaker. This works with a retention period of 14 epochs.
     * Once the retention period has passed, the stake can be withdrawn.
     */
    function requestWithdrawal(uint256[] memory _depositIds) public override {
        for (uint256 i = 0; i < _depositIds.length; i++) {
            UserStake memory userStake = userStakes[_depositIds[i]];
            require(userStake.owner == msg.sender, "BattleflyFlywheelVault: caller is not the owner");
            ATLAS_STAKER.requestWithdrawal(_depositIds[i]);
            emit RequestWithdrawal(_depositIds[i]);
        }
    }

    /**
     * @dev Claim emission from AtlasStaker
     */
    function claim(uint256 _depositId) public override nonReentrant returns (uint256 emission) {
        emission = _claim(_depositId);
    }

    /**
     * @dev Claim all emissions from AtlasStaker
     */
    function claimAll() external override nonReentrant returns (uint256 amount) {
        uint256[] memory depositIds = depositIdByUser[msg.sender].values();
        require(depositIds.length > 0, "BattleflyFlywheelVault: No deposited funds");

        for (uint256 i = 0; i < depositIds.length; i++) {
            amount += _claim(depositIds[i]);
        }
    }

    /**
     * @dev Whitelist user
     */
    function whitelistUser(address _who) public onlyOwner {
        require(!whitelistedUsers[_who], "BattlefalyWheelVault: Already whitelisted");
        whitelistedUsers[_who] = true;
        emit AddedUser(_who);
    }

    /**
     * @dev Whitelist users
     */
    function whitelistUsers(address[] memory _users) external onlyOwner {
        for (uint256 i = 0; i < _users.length; i++) {
            whitelistUser(_users[i]);
        }
    }

    /**
     * @dev Remove user from whitelist
     */
    function removeUser(address _who) public onlyOwner {
        require(whitelistedUsers[_who], "BattlefalyWheelVault: Not whitelisted yet");
        whitelistedUsers[_who] = false;
        emit RemovedUser(_who);
    }

    /**
     * @dev Remove users from whitelist
     */
    function removeUsers(address[] memory _users) external onlyOwner {
        for (uint256 i = 0; i < _users.length; i++) {
            removeUser(_users[i]);
        }
    }

    function withdrawMagic(uint256 amount, address recipient) external onlyOwner {
        MAGIC.safeTransfer(recipient, amount);
    }

    // ================ INTERNAL ================

    /**
     * @dev Withdraw a stake from AtlasStaker (Only possible when the retention period has passed)
     */
    function _withdraw(uint256 _depositId) internal returns (uint256 amount) {
        UserStake memory userStake = userStakes[_depositId];
        require(userStake.owner == msg.sender, "BattleflyFlywheelVault: caller is not the owner");
        require(ATLAS_STAKER.canWithdraw(_depositId), "BattleflyFlywheelVault: stake not yet unlocked");
        amount = ATLAS_STAKER.withdraw(_depositId);
        MAGIC.safeTransfer(msg.sender, amount);
        depositIdByUser[msg.sender].remove(_depositId);
        delete userStakes[_depositId];
        emit WithdrawPosition(_depositId, amount);
    }

    /**
     * @dev Claim emission from AtlasStaker
     */
    function _claim(uint256 _depositId) internal returns (uint256 emission) {
        UserStake memory userStake = userStakes[_depositId];
        require(userStake.owner == msg.sender, "BattleflyFlywheelVault: caller is not the owner");

        emission = ATLAS_STAKER.claim(_depositId);
        MAGIC.safeTransfer(msg.sender, emission);
        emit ClaimEmission(_depositId, emission);
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
     * @dev Get the remaining stakeable MAGIC amount.
     */
    function remainingStakeableAmount(address user) public view override returns (uint256 remaining) {
        uint256 v1Amount = FOUNDER_VAULT_V1.balanceOf(user);
        uint256 v2Amount = FOUNDER_VAULT_V2.balanceOf(user);
        uint256 eligible = (v1Amount * STAKING_LIMIT_V1) + (v2Amount * STAKING_LIMIT_V2);
        uint256 staked = getStakedAmount(user);
        remaining = eligible >= staked ? eligible - staked : 0;
    }

    /**
     * @dev Get the staked amount of a particular user.
     */
    function getStakedAmount(address user) public view override returns (uint256 amount) {
        uint256[] memory depositIds = depositIdByUser[user].values();
        for (uint256 i = 0; i < depositIds.length; i++) {
            amount += userStakes[depositIds[i]].amount;
        }
    }

    /**
     * @dev Get the deposit ids of a user.
     */
    function getDepositIdsOfUser(address user) public view override returns (uint256[] memory depositIds) {
        depositIds = depositIdByUser[user].values();
    }

    /**
     * @dev Return the name of the vault
     */
    function getName() public pure override returns (string memory) {
        return "Founders Flywheel Vault";
    }

    // ================== MODIFIERS ==================

    modifier onlyMembers() {
        if (!whitelistedUsers[msg.sender]) {
            require(
                FOUNDER_VAULT_V1.balanceOf(msg.sender) + FOUNDER_VAULT_V2.balanceOf(msg.sender) > 0,
                "BattleflyWheelVault: caller has no staked Founder NFTs"
            );
        }
        _;
    }

    // ================== EVENTS ==================
    event NewUserStake(uint256 depositId, uint256 amount, uint256 unlockAt, address owner, IAtlasMine.Lock lock);
    event UpdateUserStake(uint256 depositId, uint256 amount, uint256 unlockAt, address owner, IAtlasMine.Lock lock);
    event ClaimEmission(uint256 depositId, uint256 emission);
    event WithdrawPosition(uint256 depositId, uint256 amount);
    event RequestWithdrawal(uint256 depositId);

    event AddedUser(address vault);
    event RemovedUser(address vault);
}

