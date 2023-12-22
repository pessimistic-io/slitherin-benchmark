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
import "./ERC721HolderUpgradeable.sol";

import "./BattleflyFounderVaultV08.sol";
import "./IBattleflyAtlasStakerV02.sol";
import "./ISmolverseFlywheelVault.sol";
import "./IBattlefly.sol";
import "./IAtlasMine.sol";
import "./IBattleflyFounderVault.sol";

contract SmolverseFlywheelVault is
    ISmolverseFlywheelVault,
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    ERC721HolderUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    /**
     * @dev Immutable states
     */

    IERC20Upgradeable public MAGIC;
    IBattleflyAtlasStakerV02 public ATLAS_STAKER;

    EnumerableSetUpgradeable.AddressSet private smolverseTokenAddresses;

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

    /**
     * @dev Stakeable Smolverse tokens
     *      { address } => { SmolverseToken }
     */
    mapping(address => SmolverseToken) public smolverseTokens;

    /**
     * @dev User's staked tokens
     *      { user } => { tokenAddress } => { tokenIds }
     */
    mapping(address => mapping(address => EnumerableSetUpgradeable.UintSet)) private tokensByUser;

    function initialize(
        address _magic,
        address _atlasStaker,
        address _smols,
        address _swols,
        address _wrappedSmols,
        address _smolPets,
        address _swolPets
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __ERC721Holder_init();

        require(_magic != address(0), "SmolverseFlywheelVault: invalid address");
        require(_atlasStaker != address(0), "SmolverseFlywheelVault: invalid address");
        require(_smols != address(0), "SmolverseFlywheelVault: invalid address");
        require(_swols != address(0), "SmolverseFlywheelVault: invalid address");
        require(_wrappedSmols != address(0), "SmolverseFlywheelVault: invalid address");
        require(_smolPets != address(0), "SmolverseFlywheelVault: invalid address");
        require(_swolPets != address(0), "SmolverseFlywheelVault: invalid address");

        MAGIC = IERC20Upgradeable(_magic);
        ATLAS_STAKER = IBattleflyAtlasStakerV02(_atlasStaker);

        smolverseTokens[_smols] = SmolverseToken(true, _smols, 5000e18);
        smolverseTokenAddresses.add(_smols);
        smolverseTokens[_swols] = SmolverseToken(true, _swols, 5000e18);
        smolverseTokenAddresses.add(_swols);
        smolverseTokens[_wrappedSmols] = SmolverseToken(true, _wrappedSmols, 5000e18);
        smolverseTokenAddresses.add(_wrappedSmols);
        smolverseTokens[_smolPets] = SmolverseToken(true, _smolPets, 1000e18);
        smolverseTokenAddresses.add(_smolPets);
        smolverseTokens[_swolPets] = SmolverseToken(true, _swolPets, 1000e18);
        smolverseTokenAddresses.add(_swolPets);
    }

    /**
     * @dev Unstake Smolverse tokens
     */
    function unstake(address[] memory tokenAddresses, uint256[] memory tokenIds) external override nonReentrant {
        require(
            tokenAddresses.length == tokenIds.length,
            "SmolverseFlywheelVault: tokenAddresses and tokenIds must be equal in size"
        );
        require(tokenAddresses.length > 0, "SmolverseFlywheelVault: required to unstake at least 1 token");
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            require(
                tokensByUser[msg.sender][tokenAddresses[i]].contains(tokenIds[i]),
                "SmolverseFlywheelVault: Not owner of token"
            );
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            IERC721Upgradeable(tokenAddresses[i]).safeTransferFrom(address(this), msg.sender, tokenIds[i]);
            tokensByUser[msg.sender][tokenAddresses[i]].remove(tokenIds[i]);
            emit unstakeToken(msg.sender, tokenAddresses[i], tokenIds[i]);
        }
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
        require(depositIds.length > 0, "SmolverseFlywheelVault: No deposited funds");
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
            require(userStake.owner == msg.sender, "SmolverseFlywheelVault: caller is not the owner");
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
        require(depositIds.length > 0, "SmolverseFlywheelVault: No deposited funds");

        for (uint256 i = 0; i < depositIds.length; i++) {
            amount += _claim(depositIds[i]);
        }
    }

    /**
     * @dev Whitelist user
     */
    function whitelistUser(address _who) public onlyOwner {
        require(!whitelistedUsers[_who], "SmolverseFlywheelVault: Already whitelisted");
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
        require(whitelistedUsers[_who], "SmolverseFlywheelVault: Not whitelisted yet");
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

    /**
     * @dev Add Smolverse token
     */
    function addSmolverseToken(
        bool _enabled,
        address _token,
        uint256 _allowance
    ) external override onlyOwner {
        smolverseTokens[_token] = SmolverseToken(_enabled, _token, _allowance);
        smolverseTokenAddresses.add(_token);
    }

    /**
     * @dev Remove Smolverse token
     */
    function removeSmolverseToken(address _token) external override onlyOwner {
        smolverseTokens[_token] = SmolverseToken(false, address(0), 0);
        smolverseTokenAddresses.remove(_token);
    }

    // ================ INTERNAL ================

    /**
     * @dev Withdraw a stake from AtlasStaker (Only possible when the retention period has passed)
     */
    function _withdraw(uint256 _depositId) internal returns (uint256 amount) {
        UserStake memory userStake = userStakes[_depositId];
        require(userStake.owner == msg.sender, "SmolverseFlywheelVault: caller is not the owner");
        require(ATLAS_STAKER.canWithdraw(_depositId), "SmolverseFlywheelVault: stake not yet unlocked");
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
        require(userStake.owner == msg.sender, "SmolverseFlywheelVault: caller is not the owner");

        emission = ATLAS_STAKER.claim(_depositId);
        MAGIC.safeTransfer(msg.sender, emission);
        emit ClaimEmission(_depositId, emission);
    }

    /**
     * @dev Get the total amount of staked tokens
     */
    function _totalTokensStaked(address user) public view returns (uint256 total) {
        for (uint256 i = 0; i < smolverseTokenAddresses.length(); i++) {
            total += tokensByUser[user][smolverseTokenAddresses.at(i)].length();
        }
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
        uint256 eligible = 0;
        for (uint256 i = 0; i < smolverseTokenAddresses.length(); i++) {
            eligible +=
                tokensByUser[user][smolverseTokenAddresses.at(i)].length() *
                smolverseTokens[smolverseTokenAddresses.at(i)].allowance;
        }
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
        return "Smolverse Flywheel Vault";
    }

    /**
     * @dev Return the staked Smols, Swols and Pets of a user
     */
    function getStakedTokens(address user)
        public
        view
        override
        returns (address[] memory tokenAddresses, uint256[] memory tokenIds)
    {
        tokenAddresses = new address[](_totalTokensStaked(user));
        tokenIds = new uint256[](_totalTokensStaked(user));
        uint256 index = 0;
        for (uint256 i = 0; i < smolverseTokenAddresses.length(); i++) {
            for (uint256 j = 0; j < tokensByUser[user][smolverseTokenAddresses.at(i)].length(); j++) {
                tokenAddresses[index] = smolverseTokenAddresses.at(i);
                tokenIds[index] = tokensByUser[user][smolverseTokenAddresses.at(i)].at(j);
                index++;
            }
        }
    }

    /**
     * @dev Check if user is the owner of the token
     */
    function isOwner(
        address tokenAddress,
        uint256 tokenId,
        address user
    ) public view override returns (bool) {
        return tokensByUser[user][tokenAddress].contains(tokenId);
    }

    // ================== MODIFIERS ==================

    modifier onlyMembers() {
        if (!whitelistedUsers[msg.sender]) {
            require(
                _totalTokensStaked(msg.sender) > 0,
                "SmolverseFlywheelVault: caller has no staked Smolverse tokens"
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
    event stakeToken(address user, address tokenAddress, uint256 tokenId);
    event unstakeToken(address user, address tokenAddress, uint256 tokenId);

    event AddedUser(address vault);
    event RemovedUser(address vault);
}

