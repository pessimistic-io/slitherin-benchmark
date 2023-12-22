// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IERC1155Upgradeable.sol";
import "./IERC721Upgradeable.sol";
import "./Initializable.sol";
import "./AddressUpgradeable.sol";
import "./SafeCastUpgradeable.sol";
import "./EnumerableSetUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./OwnableUpgradeable.sol";

import "./IBattleflyAtlasStaker.sol";
import "./IAtlasMine.sol";
import "./ISpecialNFT.sol";
import "./IBattleflyVault.sol";

contract BattleflyVault is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;
    using SafeCastUpgradeable for uint256;
    using SafeCastUpgradeable for int256;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    // ============================================ STATE ==============================================
    struct UserStake {
        uint256 amount;
        uint256 unlockAt;
        uint256 withdrawAt;
        IAtlasMine.Lock lock;
        uint256 battleflyStakerDepositId;
        address owner;
    }
    // ============= Global Immutable State ==============
    IERC20Upgradeable public magic;
    IBattleflyAtlasStaker public BattleflyStaker;
    // ============= Global Staking State ==============
    mapping(uint256 => UserStake) public userStakes;
    mapping(address => EnumerableSetUpgradeable.UintSet) private stakesOfOwner;
    uint256 nextStakeId;
    uint256 public totalStaked;

    // ============= Global Admin ==============
    mapping(address => bool) private adminAccess;
    // ============================================ EVENT ==============================================
    event Claim(address indexed user, uint256 stakeId, uint256 amount);
    event Stake(address indexed user, uint256 stakeId, uint256 amount, IAtlasMine.Lock lock);
    event Withdraw(address indexed user, uint256 stakeId, uint256 amount);
    event SetFee(uint256 oldFee, uint256 newFee, uint256 denominator);
    event WithdrawFee(address receiver, uint256 amount);

    event SetAdminAccess(address indexed user, bool access);

    // ============================================ INITIALIZE ==============================================
    function initialize(address _magicAddress, address _BattleflyStakerAddress) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        magic = IERC20Upgradeable(_magicAddress);
        BattleflyStaker = IBattleflyAtlasStaker(_BattleflyStakerAddress);
        nextStakeId = 0;
        // Approve the AtlasStaker contract to spend the magic
        magic.safeApprove(address(BattleflyStaker), 2**256 - 1);
    }

    // ============================================ USER FUNCTIONS ==============================================
    function stake(uint256 amount, IAtlasMine.Lock lock) external {
        magic.safeTransferFrom(msg.sender, address(this), amount);
        _stake(amount, lock);
    }

    function _stake(uint256 amount, IAtlasMine.Lock lock) internal returns (uint256) {
        require(amount > 0, "Amount must be greater than 0");
        uint256 battleflyStakerDepositId = BattleflyStaker.deposit(amount, lock);
        IBattleflyAtlasStaker.VaultStake memory vaultStake = BattleflyStaker.getVaultStake(
            address(this),
            battleflyStakerDepositId
        );
        UserStake storage s = userStakes[nextStakeId];
        s.amount = amount;
        s.unlockAt = vaultStake.unlockAt;
        s.lock = lock;
        s.battleflyStakerDepositId = battleflyStakerDepositId;
        s.owner = msg.sender;
        stakesOfOwner[msg.sender].add(nextStakeId);
        emit Stake(msg.sender, nextStakeId, amount, lock);
        nextStakeId++;
        totalStaked += amount;
        return nextStakeId - 1;
    }

    function claimAll() public nonReentrant {
        uint256 totalReward = 0;
        for (uint256 i = 0; i < stakesOfOwner[msg.sender].length(); i++) {
            uint256 stakeId = stakesOfOwner[msg.sender].at(i);
            if (_getStakeClaimableAmount(stakeId) > 0) {
                totalReward += _claim(stakeId);
            }
        }
        require(totalReward > 0, "No rewards to claim");
        magic.safeTransfer(msg.sender, totalReward);
    }

    function claimAllAndRestake(IAtlasMine.Lock lock) external {
        uint256 totalReward = 0;
        for (uint256 i = 0; i < stakesOfOwner[msg.sender].length(); i++) {
            uint256 stakeId = stakesOfOwner[msg.sender].at(i);
            if (_getStakeClaimableAmount(stakeId) > 0) {
                totalReward += _claim(stakeId);
            }
        }
        require(totalReward > 0, "No rewards to claim");
        _stake(totalReward, lock);
    }

    function claim(uint256[] memory stakeIds) external nonReentrant {
        uint256 totalReward = 0;
        for (uint256 i = 0; i < stakeIds.length; i++) {
            UserStake storage s = userStakes[stakeIds[i]];
            require(s.owner == msg.sender, "Only the owner can claim");
            if (_getStakeClaimableAmount(stakeIds[i]) > 0) {
                totalReward += _claim(stakeIds[i]);
            }
        }
        require(totalReward > 0, "No rewards to claim");
        magic.safeTransfer(msg.sender, totalReward);
    }

    function _claim(uint256 stakeId) internal returns (uint256) {
        UserStake memory s = userStakes[stakeId];
        uint256 claimedAmount = BattleflyStaker.claim(s.battleflyStakerDepositId);
        emit Claim(s.owner, stakeId, claimedAmount);
        return claimedAmount;
    }

    function _getStakeClaimableAmount(uint256 stakeId) internal view returns (uint256) {
        UserStake memory s = userStakes[stakeId];
        uint256 claimAmount = BattleflyStaker.pendingRewards(address(this), s.battleflyStakerDepositId);
        return claimAmount;
    }

    function getUserClaimableAmount(address user) external view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < stakesOfOwner[user].length(); i++) {
            uint256 stakeId = stakesOfOwner[user].at(i);
            total += _getStakeClaimableAmount(stakeId);
        }
        return total;
    }

    function getUserStakes(address user) external view returns (UserStake[] memory) {
        UserStake[] memory stakes = new UserStake[](stakesOfOwner[user].length());
        for (uint256 i = 0; i < stakesOfOwner[user].length(); i++) {
            uint256 stakeId = stakesOfOwner[user].at(i);
            stakes[i] = userStakes[stakeId];
        }
        return stakes;
    }

    function withdrawAll() external nonReentrant {
        require(stakesOfOwner[msg.sender].length() > 0, "No stakes to withdraw");
        uint256 receiveAmount;
        for (uint256 i = 0; i < stakesOfOwner[msg.sender].length(); i++) {
            uint256 stakeId = stakesOfOwner[msg.sender].at(i);
            if (userStakes[stakeId].unlockAt < block.timestamp) {
                receiveAmount += _withdraw(stakeId);
            }
        }
        require(receiveAmount > 0, "No stakes to withdraw");
        magic.safeTransfer(msg.sender, receiveAmount);
    }

    function withdraw(uint256[] memory stakeIds) external nonReentrant {
        uint256 receiveAmount;
        for (uint256 i = 0; i < stakeIds.length; i++) {
            UserStake storage s = userStakes[stakeIds[i]];
            require(s.owner == msg.sender, "Only the owner can withdraw");
            receiveAmount += _withdraw(stakeIds[i]);
        }
        require(receiveAmount > 0, "No stakes to withdraw");
        magic.safeTransfer(msg.sender, receiveAmount);
    }

    function _withdraw(uint256 stakeId) internal returns (uint256 withdrawAmount) {
        UserStake storage s = userStakes[stakeId];
        withdrawAmount = s.amount;
        require(s.unlockAt < block.timestamp, "Cannot withdraw before the lock time");
        uint256 claimableAmount = _getStakeClaimableAmount(stakeId);
        if (claimableAmount > 0) {
            withdrawAmount += _claim(stakeId);
        }
        BattleflyStaker.withdraw(s.battleflyStakerDepositId);
        totalStaked -= s.amount;
        stakesOfOwner[msg.sender].remove(stakeId);
        s.withdrawAt = block.timestamp;
        emit Withdraw(msg.sender, stakeId, withdrawAmount);
    }

    // ============================================ OWNER FUNCTIONS ==============================================
    function setAdminAccess(address user, bool access) external onlyOwner {
        adminAccess[user] = access;
        emit SetAdminAccess(user, access);
    }

    // ============================================ MODIFIER ==============================================
    modifier onlyAdminAccessOrOwner() {
        require(adminAccess[_msgSender()] == true || _msgSender() == owner(), "Require admin access");
        _;
    }
}

