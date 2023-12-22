// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./MerkleProofUpgradeable.sol";
import "./EnumerableSetUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

import "./BattleflyFounderVaultV08.sol";
import "./IBattleflyAtlasStakerV02.sol";
import "./IBattleflyFlywheelVaultV02.sol";
import "./IAtlasMine.sol";

contract BattleflyFlywheelVaultV02 is
    IBattleflyFlywheelVaultV02,
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    /**
     * @dev Immutable states
     */
    IERC20Upgradeable public MAGIC;
    IBattleflyAtlasStakerV02 public ATLAS_STAKER;

    string public name;

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

    function initialize(address _atlasStaker, string memory _name) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        require(_atlasStaker != address(0), "BattleflyFlywheelVault: invalid address");
        require(bytes(_name).length > 0, "BattleflyFlywheelVault: invalid name");

        ATLAS_STAKER = IBattleflyAtlasStakerV02(_atlasStaker);
        MAGIC = ATLAS_STAKER.MAGIC();

        name = _name;
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
    function withdraw(uint256[] calldata _depositIds) public override nonReentrant returns (uint256 amount) {
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
    function requestWithdrawal(uint256[] calldata _depositIds) public override {
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
    function whitelistUsers(address[] calldata _users) external onlyOwner {
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
    function removeUsers(address[] calldata _users) external onlyOwner {
        for (uint256 i = 0; i < _users.length; i++) {
            removeUser(_users[i]);
        }
    }

    /**
     * @dev Set the name of the vault
     */
    function setName(string memory _name) public onlyOwner {
        name = _name;
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
     * @dev Get the depositIds of a user
     */
    function depositIdsOfUser(address user) public view override returns (uint256[] memory depositIds) {
        return depositIdByUser[user].values();
    }

    /**
     * @dev Return the name of the vault
     */
    function getName() public view override returns (string memory) {
        return name;
    }

    // ================== MODIFIERS ==================

    modifier onlyMembers() {
        require(whitelistedUsers[msg.sender], "BattleflyWheelVault: caller is not a whitelisted member");
        _;
    }
}

