// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IERC1155Upgradeable.sol";
import "./ERC1155HolderUpgradeable.sol";
import "./IERC721Upgradeable.sol";
import "./ERC721HolderUpgradeable.sol";
import "./Initializable.sol";
import "./AddressUpgradeable.sol";
import "./SafeCastUpgradeable.sol";
import "./EnumerableSetUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./OwnableUpgradeable.sol";

import "./IBattleflyAtlasStaker.sol";
import "./IAtlasMine.sol";
import "./ISpecialNFT.sol";
import "./IBattleflyFounderVault.sol";
import "./IBattleflyFlywheelVault.sol";

contract BattleflyFounderVault is
    Initializable,
    OwnableUpgradeable,
    ERC1155HolderUpgradeable,
    ERC721HolderUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;
    using SafeCastUpgradeable for uint256;
    using SafeCastUpgradeable for int256;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    // ============================================ STATE ==============================================
    struct FounderStake {
        uint256 amount;
        uint256 stakeTimestamp;
        address owner;
        uint256 lastClaimedDay;
    }
    struct DailyFounderEmission {
        uint256 totalEmission;
        uint256 totalFounders;
    }
    // ============= Global Immutable State ==============

    /// @notice MAGIC token
    /// @dev functionally immutable
    IERC20Upgradeable public magic;
    ISpecialNFT public founderNFT;
    uint256 public founderTypeID;
    IBattleflyAtlasStaker public BattleflyStaker;
    uint256 public startTimestamp;
    // ============= Global mutable State ==============
    uint256 totalEmission;
    uint256 claimedEmission;
    uint256 pendingFounderEmission;

    mapping(address => EnumerableSetUpgradeable.UintSet) private FounderStakeOfOwner;
    uint256 lastStakeTimestamp;
    mapping(uint256 => FounderStake) public FounderStakes;
    uint256 lastStakeId;
    mapping(address => bool) private adminAccess;
    uint256 public DaysSinceStart;
    mapping(uint256 => DailyFounderEmission) public DailyFounderEmissions;

    uint256 withdrawnOldFounder;
    uint256 unupdatedStakeIdFrom;

    uint256 public stakeBackPercent;
    uint256 public treasuryPercent;
    uint256 public v2VaultPercent;

    IBattleflyFounderVault battleflyFounderVaultV2;
    IBattleflyFlywheelVault battleflyFlywheelVault;
    // ============= Constant ==============
    address public constant TREASURY_WALLET = 0xF5411006eEfD66c213d2fd2033a1d340458B7226;
    uint256 public constant PERCENT_DENOMINATOR = 10000;
    IAtlasMine.Lock public constant DEFAULT_STAKE_BACK_LOCK = IAtlasMine.Lock.twoWeeks;

    mapping(uint256 => bool) public claimedPastEmission;
    uint256 public pastEmissionPerFounder;
    mapping(uint256 => uint256) public stakeIdOfFounder;
    mapping(uint256 => EnumerableSetUpgradeable.UintSet) stakingFounderOfStakeId;

    // ============================================ EVENTS ==============================================
    event ClaimDailyEmission(
        uint256 dayTotalEmission,
        uint256 totalFounderEmission,
        uint256 totalFounders,
        uint256 stakeBackAmount,
        uint256 treasuryAmount,
        uint256 v2VaultAmount
    );
    event Claim(address user, uint256 stakeId, uint256 amount);
    event Withdraw(address user, uint256 stakeId, uint256 founderId);
    event Stake(address user, uint256 stakeId, uint256[] founderNFTIDs);
    event TopupMagicToStaker(address user, uint256 amount, IAtlasMine.Lock lock);
    event TopupTodayEmission(address user, uint256 amount);
    event ClaimPastEmission(address user, uint256 amount, uint256[] tokenIds);

    // ============================================ INITIALIZE ==============================================
    function initialize(
        address _magicAddress,
        address _BattleflyStakerAddress,
        uint256 _founderTypeID,
        address _founderNFTAddress,
        uint256 _startTimestamp,
        address _battleflyFounderVaultV2Address,
        uint256 _stakeBackPercent,
        uint256 _treasuryPercent,
        uint256 _v2VaultPercent
    ) external initializer {
        __ERC1155Holder_init();
        __ERC721Holder_init();
        __Ownable_init();
        __ReentrancyGuard_init();

        magic = IERC20Upgradeable(_magicAddress);
        BattleflyStaker = IBattleflyAtlasStaker(_BattleflyStakerAddress);
        founderNFT = (ISpecialNFT(_founderNFTAddress));
        founderTypeID = _founderTypeID;
        lastStakeTimestamp = block.timestamp;
        lastStakeId = 0;
        startTimestamp = _startTimestamp;
        DaysSinceStart = 0;
        stakeBackPercent = _stakeBackPercent;
        treasuryPercent = _treasuryPercent;
        v2VaultPercent = _v2VaultPercent;
        if (_battleflyFounderVaultV2Address == address(0))
            battleflyFounderVaultV2 = IBattleflyFounderVault(address(this));
        else battleflyFounderVaultV2 = IBattleflyFounderVault(_battleflyFounderVaultV2Address);

        require(stakeBackPercent + treasuryPercent + v2VaultPercent < PERCENT_DENOMINATOR);

        // Approve the AtlasStaker contract to spend the magic
        magic.safeApprove(address(BattleflyStaker), 2**256 - 1);
    }

    // ============================================ USER OPERATIONS ==============================================
    function claimPastEmission() external {
        require(pastEmissionPerFounder != 0, "No past founder emission to claim");
        uint256[] memory tokenIds = getPastEmissionClaimableTokens(msg.sender);
        require(tokenIds.length > 0, "No tokens to claim");
        for (uint256 i = 0; i < tokenIds.length; i++) {
            claimedPastEmission[tokenIds[i]] = true;
        }
        magic.safeTransfer(msg.sender, pastEmissionPerFounder * tokenIds.length);
        emit ClaimPastEmission(msg.sender, pastEmissionPerFounder * tokenIds.length, tokenIds);
    }

    function getPastEmissionClaimableTokens(address user) public view returns (uint256[] memory) {
        uint256 balance = founderNFT.balanceOf(user);
        uint256[] memory tokenIds = new uint256[](balance);
        uint256 countClaimable = 0;
        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = founderNFT.tokenOfOwnerByIndex(user, i);
            uint256 tokenType = founderNFT.getSpecialNFTType(tokenId);
            if (tokenType == founderTypeID && claimedPastEmission[tokenId] == false) {
                tokenIds[countClaimable] = tokenId;
                countClaimable++;
            }
        }
        (, uint256[][] memory stakeTokens) = stakesOf(user);
        uint256 countClaimableStaked = 0;
        uint256 balanceStaked = 0;
        for (uint256 i = 0; i < stakeTokens.length; i++) {
            balanceStaked += stakeTokens[i].length;
        }
        uint256[] memory stakingTokenIds = new uint256[](balanceStaked);
        for (uint256 i = 0; i < stakeTokens.length; i++) {
            uint256[] memory stakeTokenIds = stakeTokens[i];
            for (uint256 j = 0; j < stakeTokenIds.length; j++) {
                uint256 tokenId = stakeTokenIds[j];
                uint256 tokenType = founderNFT.getSpecialNFTType(tokenId);
                if (tokenType == founderTypeID && claimedPastEmission[tokenId] == false) {
                    stakingTokenIds[countClaimableStaked] = tokenId;
                    countClaimableStaked++;
                }
            }
        }

        uint256[] memory result = new uint256[](countClaimable + countClaimableStaked);
        for (uint256 i = 0; i < countClaimable; i++) {
            result[i] = tokenIds[i];
        }
        for (uint256 i = countClaimable; i < countClaimable + countClaimableStaked; i++) {
            result[i] = stakingTokenIds[i - countClaimable];
        }
        return result;
    }

    function setTokenClaimedPastEmission(uint256[] memory tokenIds, bool isClaimed) external onlyOwner {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            claimedPastEmission[tokenIds[i]] = isClaimed;
        }
    }

    function setPastEmission(uint256 amount) external onlyOwner {
        pastEmissionPerFounder = amount;
    }

    function stakesOf(address owner) public view returns (FounderStake[] memory, uint256[][] memory) {
        FounderStake[] memory stakes = new FounderStake[](FounderStakeOfOwner[owner].length());
        uint256[][] memory _founderIDsOfStake = new uint256[][](FounderStakeOfOwner[owner].length());
        for (uint256 i = 0; i < FounderStakeOfOwner[owner].length(); i++) {
            stakes[i] = FounderStakes[FounderStakeOfOwner[owner].at(i)];
            _founderIDsOfStake[i] = stakingFounderOfStakeId[FounderStakeOfOwner[owner].at(i)].values();
        }
        return (stakes, _founderIDsOfStake);
    }

    function stakeFounderNFT(uint256[] memory ids) external {
        require(ids.length != 0, "Must provide at least one founder NFT ID");
        for (uint256 i = 0; i < ids.length; i++) {
            require(founderNFT.getSpecialNFTType(ids[i]) == founderTypeID, "Not valid founder NFT");
            founderNFT.safeTransferFrom(msg.sender, address(this), ids[i]);
        }
        uint256 currentDay = (block.timestamp - startTimestamp) / 24 hours;
        lastStakeId++;
        FounderStakes[lastStakeId] = (
            FounderStake({
                amount: ids.length,
                stakeTimestamp: block.timestamp,
                owner: msg.sender,
                lastClaimedDay: currentDay
            })
        );
        for (uint256 i = 0; i < ids.length; i++) {
            stakeIdOfFounder[ids[i]] = lastStakeId;
            stakingFounderOfStakeId[lastStakeId].add(ids[i]);
        }
        FounderStakeOfOwner[msg.sender].add(lastStakeId);
        emit Stake(msg.sender, lastStakeId, ids);
    }

    function claimAll() external nonReentrant {
        uint256 totalReward = 0;
        for (uint256 i = 0; i < FounderStakeOfOwner[msg.sender].length(); i++) {
            totalReward += _claimByStakeId(FounderStakeOfOwner[msg.sender].at(i));
        }
        require(totalReward > 0, "No reward to claim");
    }

    function withdrawAll() external nonReentrant {
        require(FounderStakeOfOwner[msg.sender].length() > 0, "No STAKE to withdraw");
        uint256 totalWithdraw = 0;
        for (uint256 i = 0; i < FounderStakeOfOwner[msg.sender].length(); i++) {
            uint256 stakeId = FounderStakeOfOwner[msg.sender].at(i);
            _claimByStakeId(stakeId);
            totalWithdraw += FounderStakes[stakeId].amount;
            _withdrawByStakeId(stakeId);
        }
        (uint256 stakeableAmount, uint256 stakingAmount) = battleflyFlywheelVault.getStakeAmount(msg.sender);
        uint256 stakeableAmountPerFounder = battleflyFlywheelVault.stakeableAmountPerFounder(address(this));
        require(
            stakingAmount <= stakeableAmount - stakeableAmountPerFounder * totalWithdraw,
            "Pls withdraw FlywheelVault first"
        );
    }

    function _withdrawByStakeId(uint256 stakeId) internal {
        FounderStake storage stake = FounderStakes[stakeId];
        _claimByStakeId(stakeId);
        for (uint256 i = 0; i < stakingFounderOfStakeId[stakeId].length(); i++) {
            founderNFT.safeTransferFrom(address(this), stake.owner, stakingFounderOfStakeId[stakeId].at(i));
            emit Withdraw(stake.owner, stakeId, stakingFounderOfStakeId[stakeId].at(i));
        }
        if (stake.stakeTimestamp < (startTimestamp + (DaysSinceStart) * 24 hours - 24 hours)) {
            withdrawnOldFounder += stakingFounderOfStakeId[stakeId].length();
        }
        FounderStakeOfOwner[stake.owner].remove(stakeId);
        delete FounderStakes[stakeId];
        delete stakingFounderOfStakeId[stakeId];
    }

    function _claimByStakeId(uint256 stakeId) internal returns (uint256) {
        require(stakeId != 0, "No stake to claim");
        FounderStake storage stake = FounderStakes[stakeId];
        uint256 totalReward = _getClaimableEmissionOf(stakeId);
        claimedEmission += totalReward;
        stake.lastClaimedDay = DaysSinceStart;
        magic.safeTransfer(stake.owner, totalReward);
        emit Claim(stake.owner, stakeId, totalReward);
        return totalReward;
    }

    function withdraw(uint256[] memory founderIds) external nonReentrant {
        require(founderIds.length > 0, "No Founder to withdraw");
        uint256 totalWithdraw = 0;
        for (uint256 i = 0; i < founderIds.length; i++) {
            uint256 stakeId = stakeIdOfFounder[founderIds[i]];
            require(FounderStakes[stakeId].owner == msg.sender, "Not your stake");
            _claimBeforeWithdraw(founderIds[i]);
            _withdraw(founderIds[i]);
            totalWithdraw++;
        }
        // (uint256 stakeableAmount, uint256 stakingAmount) = battleflyFlywheelVault.getStakeAmount(msg.sender);
        // uint256 stakeableAmountPerFounder = battleflyFlywheelVault.stakeableAmountPerFounder(address(this));
        // require(stakingAmount <= stakeableAmount - stakeableAmountPerFounder * totalWithdraw, "Pls withdraw FlywheelVault first");
    }

    function _claimBeforeWithdraw(uint256 founderId) internal returns (uint256) {
        uint256 stakeId = stakeIdOfFounder[founderId];
        FounderStake storage stake = FounderStakes[stakeId];
        uint256 founderReward = _getClaimableEmissionOf(stakeId) / stake.amount;
        claimedEmission += founderReward;
        magic.safeTransfer(stake.owner, founderReward);
        emit Claim(stake.owner, stakeId, founderReward);
        return founderReward;
    }

    function getClaimableEmissionOf(address user) public view returns (uint256) {
        uint256 totalReward = 0;
        for (uint256 i = 0; i < FounderStakeOfOwner[user].length(); i++) {
            totalReward += _getClaimableEmissionOf(FounderStakeOfOwner[user].at(i));
        }
        return totalReward;
    }

    function _getClaimableEmissionOf(uint256 stakeId) internal view returns (uint256) {
        uint256 totalReward = 0;
        FounderStake memory stake = FounderStakes[stakeId];
        if (stake.lastClaimedDay == DaysSinceStart) return 0;
        for (uint256 j = stake.lastClaimedDay + 1; j <= DaysSinceStart; j++) {
            if (DailyFounderEmissions[j].totalFounders == 0 || stake.amount == 0) continue;
            totalReward +=
                (DailyFounderEmissions[j].totalEmission / DailyFounderEmissions[j].totalFounders) *
                stake.amount;
        }
        return totalReward;
    }

    function _withdraw(uint256 founderId) internal {
        uint256 stakeId = stakeIdOfFounder[founderId];
        FounderStake storage stake = FounderStakes[stakeId];
        // _claim(founderId);
        founderNFT.safeTransferFrom(address(this), stake.owner, founderId);
        stake.amount--;
        delete stakeIdOfFounder[founderId];
        stakingFounderOfStakeId[stakeId].remove(founderId);
        if (stake.stakeTimestamp < (startTimestamp + (DaysSinceStart) * 24 hours - 24 hours)) {
            withdrawnOldFounder += 1;
        }
        if (stake.amount == 0) {
            FounderStakeOfOwner[stake.owner].remove(stakeId);
            delete FounderStakes[stakeId];
        }
        emit Withdraw(stake.owner, stakeId, founderId);
    }

    // ============================================ ADMIN OPERATIONS ==============================================
    function topupMagicToStaker(uint256 amount, IAtlasMine.Lock lock) external onlyAdminAccess {
        require(amount > 0);
        magic.safeTransferFrom(msg.sender, address(this), amount);
        _depositToStaker(amount, lock);
        emit TopupMagicToStaker(msg.sender, amount, lock);
    }

    function topupTodayEmission(uint256 amount) external onlyAdminAccess {
        require(amount > 0);
        magic.safeTransferFrom(msg.sender, address(this), amount);
        pendingFounderEmission += amount;
        emit TopupTodayEmission(msg.sender, amount);
    }

    function depositToStaker(uint256 amount, IAtlasMine.Lock lock) external onlyAdminAccess {
        require(magic.balanceOf(address(this)) >= amount);
        require(amount > 0);
        _depositToStaker(amount, lock);
    }

    function _depositToStaker(uint256 amount, IAtlasMine.Lock lock) internal {
        BattleflyStaker.deposit(amount, lock);
    }

    function claimDailyEmission() public onlyAdminAccess nonReentrant {
        uint256 currentDay = (block.timestamp - startTimestamp) / 24 hours;
        require(currentDay > DaysSinceStart, "Cant claim again for today");
        uint256 todayTotalEmission = BattleflyStaker.claimAll();
        uint256 todayTotalFounderNFTs = _updateTotalStakingFounders(currentDay);

        uint256 stakeBackAmount;
        uint256 v2VaultAmount;
        uint256 treasuryAmount;
        uint256 founderEmission;
        if (todayTotalEmission != 0) {
            stakeBackAmount = (todayTotalEmission * stakeBackPercent) / PERCENT_DENOMINATOR;
            if (stakeBackAmount != 0) _depositToStaker(stakeBackAmount, DEFAULT_STAKE_BACK_LOCK);

            v2VaultAmount = (todayTotalEmission * v2VaultPercent) / PERCENT_DENOMINATOR;
            if (v2VaultAmount != 0) battleflyFounderVaultV2.topupMagicToStaker(v2VaultAmount, DEFAULT_STAKE_BACK_LOCK);

            treasuryAmount = (todayTotalEmission * treasuryPercent) / PERCENT_DENOMINATOR;
            if (treasuryAmount != 0) magic.safeTransfer(TREASURY_WALLET, treasuryAmount);

            founderEmission += todayTotalEmission - stakeBackAmount - v2VaultAmount - treasuryAmount;
        }
        if (pendingFounderEmission > 0) {
            founderEmission += pendingFounderEmission;
            pendingFounderEmission = 0;
        }
        totalEmission += founderEmission;
        DaysSinceStart = currentDay;
        DailyFounderEmissions[DaysSinceStart] = DailyFounderEmission({
            totalEmission: founderEmission,
            totalFounders: todayTotalFounderNFTs
        });
        emit ClaimDailyEmission(
            todayTotalEmission,
            founderEmission,
            todayTotalFounderNFTs,
            stakeBackAmount,
            treasuryAmount,
            v2VaultAmount
        );
    }

    function withdrawAllFromStaker() external onlyAdminAccess {
        claimDailyEmission();
        BattleflyStaker.withdrawAll();
    }

    function withdrawFromVault(address receiver, uint256 amount) external onlyAdminAccess {
        magic.safeTransfer(receiver, amount);
    }

    function _updateTotalStakingFounders(uint256 currentDay) private returns (uint256) {
        uint256 result = DailyFounderEmissions[DaysSinceStart].totalFounders - withdrawnOldFounder;
        withdrawnOldFounder = 0;
        uint256 to = startTimestamp + currentDay * 24 hours;
        uint256 i = unupdatedStakeIdFrom;
        for (; i <= lastStakeId; i++) {
            if (FounderStakes[i].stakeTimestamp == 0) {
                continue;
            }
            if (FounderStakes[i].stakeTimestamp > to) {
                break;
            }
            result += FounderStakes[i].amount;
        }
        unupdatedStakeIdFrom = i;
        return result;
    }

    //Must be called right after init
    function setFlywheelVault(address vault) external onlyOwner {
        require(vault != address(0));
        battleflyFlywheelVault = IBattleflyFlywheelVault(vault);
    }

    function setAdminAccess(address user, bool access) external onlyOwner {
        adminAccess[user] = access;
    }

    modifier onlyAdminAccess() {
        require(adminAccess[_msgSender()] || _msgSender() == owner(), "Require admin access");
        _;
    }
}

