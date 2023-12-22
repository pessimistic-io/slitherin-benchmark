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
import "./IBattleflyFounderVault.sol";

contract BattleflyFlywheelVault is IBattleflyVault, Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
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
        uint256 battleflyStakerDepositId;
        address owner;
        IAtlasMine.Lock lock;
    }
    // ============= Global Immutable State ==============
    IERC20Upgradeable public magic;
    IBattleflyAtlasStaker public BattleflyStaker;
    // ============= Global Staking State ==============
    mapping(uint256 => UserStake) public userStakes;
    mapping(address => EnumerableSetUpgradeable.UintSet) private stakesOfOwner;
    uint256 public nextStakeId;
    uint256 public totalStaked;
    uint256 public totalFee;
    uint256 public totalFeeWithdrawn;
    uint256 public FEE;
    uint256 public FEE_DENOMINATOR;
    // ============= Global Admin ==============
    mapping(address => bool) private adminAccess;

    address public TREASURY_WALLET;
    IBattleflyFounderVault public founderVaultV1;
    IBattleflyFounderVault public founderVaultV2;
    uint256 public stakeableAmountPerV1;
    uint256 public stakeableAmountPerV2;
    // ============================================ EVENT ==============================================
    event Claim(address indexed user, uint256 stakeId, uint256 amount, uint256 fee);
    event Stake(address indexed user, uint256 stakeId, uint256 amount, IAtlasMine.Lock lock);
    event Withdraw(address indexed user, uint256 stakeId, uint256 amount);
    event SetFee(uint256 oldFee, uint256 newFee, uint256 denominator);
    event WithdrawFee(address receiver, uint256 amount);

    event SetAdminAccess(address indexed user, bool access);

    // ============================================ INITIALIZE ==============================================
    function initialize(
        address _magicAddress,
        address _BattleflyStakerAddress,
        uint256 _fee,
        uint256 _feeDominator,
        address _founderVaultV1Address,
        address _founderVaultV2Address,
        uint256 _stakeableAmountPerV1,
        uint256 _stakeableAmountPerV2
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        magic = IERC20Upgradeable(_magicAddress);
        BattleflyStaker = IBattleflyAtlasStaker(_BattleflyStakerAddress);
        nextStakeId = 0;
        FEE_DENOMINATOR = _feeDominator;
        founderVaultV1 = IBattleflyFounderVault(_founderVaultV1Address);
        founderVaultV2 = IBattleflyFounderVault(_founderVaultV2Address);
        stakeableAmountPerV1 = _stakeableAmountPerV1;
        stakeableAmountPerV2 = _stakeableAmountPerV2;
        TREASURY_WALLET = 0xF5411006eEfD66c213d2fd2033a1d340458B7226;
        // Approve the AtlasStaker contract to spend the magic
        magic.safeApprove(address(BattleflyStaker), 2**256 - 1);

        _setFee(_fee);
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
        s.battleflyStakerDepositId = battleflyStakerDepositId;
        s.owner = msg.sender;
        s.lock = lock;
        stakesOfOwner[msg.sender].add(nextStakeId);
        emit Stake(msg.sender, nextStakeId, amount, lock);
        nextStakeId++;
        totalStaked += amount;
        return nextStakeId - 1;
    }

    function getStakeAmount(address user) public view returns (uint256, uint256) {
        uint256 totalStakingV1;
        uint256 totalStakingV2;
        IBattleflyFounderVault.FounderStake[] memory v1Stakes = founderVaultV1.stakesOf(user);
        IBattleflyFounderVault.FounderStake[] memory v2Stakes = founderVaultV2.stakesOf(user);
        for (uint256 i = 0; i < v1Stakes.length; i++) {
            totalStakingV1 += v1Stakes[i].amount;
        }
        for (uint256 i = 0; i < v2Stakes.length; i++) {
            totalStakingV2 += v2Stakes[i].amount;
        }
        uint256 totalUserStaking = 0;
        for (uint256 i = 0; i < stakesOfOwner[user].length(); i++) {
            uint256 stakeId = stakesOfOwner[user].at(i);
            totalUserStaking += userStakes[stakeId].amount;
        }
        uint256 stakedAmount = totalStakingV1 * stakeableAmountPerV1 + totalStakingV2 * stakeableAmountPerV2;
        return (stakedAmount, totalUserStaking);
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
        uint256 fee = (claimedAmount * FEE) / FEE_DENOMINATOR;
        uint256 userClaimAmount = claimedAmount - fee;
        totalFee += fee;
        emit Claim(s.owner, stakeId, userClaimAmount, fee);
        return userClaimAmount;
    }

    function _getStakeClaimableAmount(uint256 stakeId) internal view returns (uint256) {
        UserStake memory s = userStakes[stakeId];
        uint256 claimAmount = BattleflyStaker.pendingRewards(address(this), s.battleflyStakerDepositId);
        uint256 fee = (claimAmount * FEE) / FEE_DENOMINATOR;
        uint256 userClaimAmount = claimAmount - fee;
        return userClaimAmount;
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

    function stakeableAmountPerFounder(address vault) external view returns (uint256) {
        if (vault == address(founderVaultV1)) {
            return stakeableAmountPerV1;
        }
        if (vault == address(founderVaultV2)) {
            return stakeableAmountPerV2;
        }
        return 0;
    }

    // ============================================ ADMIN FUNCTIONS ==============================================
    function setFee(uint256 _fee) external onlyAdminAccessOrOwner {
        _setFee(_fee);
        require(totalStaked == 0, "Fee can only be updated without any stakers");
        emit SetFee(FEE, _fee, FEE_DENOMINATOR);
    }

    function _setFee(uint256 _fee) private {
        require(_fee < FEE_DENOMINATOR, "Fee must be less than the fee dominator");

        FEE = _fee;
    }

    function setTreasuryWallet(address _treasuryWallet) external onlyAdminAccessOrOwner {
        TREASURY_WALLET = _treasuryWallet;
    }

    function withdrawFeeToTreasury() external onlyAdminAccessOrOwner {
        uint256 amount = totalFee - totalFeeWithdrawn;
        require(amount > 0, "No fee to withdraw");
        totalFeeWithdrawn += amount;
        magic.safeTransfer(TREASURY_WALLET, amount);
        emit WithdrawFee(TREASURY_WALLET, amount);
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

