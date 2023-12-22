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
import "./IBattleflyAtlasStakerV02.sol";
import "./IAtlasMine.sol";
import "./ISpecialNFT.sol";
import "./IBattleflyFounderVault.sol";
import "./IBattleflyFlywheelVault.sol";
import "./IBattleflyFoundersFlywheelVault.sol";
import "./IBattleflyTreasuryFlywheelVault.sol";
import "./IBattleflyHarvesterEmissions.sol";

contract BattleflyFounderVaultV08 is
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
    // ---- !!! Not Used Anymore !!! ----
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
    // ---- !!! Not Used Anymore !!! ----
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

    // Upgrade Atlas Staker Start

    bool public claimingIsPaused;

    EnumerableSetUpgradeable.UintSet depositIds;
    // ---- !!! New Versions !!! ----
    IBattleflyAtlasStakerV02 public BattleflyStakerV2;
    IBattleflyFoundersFlywheelVault public BattleflyFoundersFlywheelVault;
    IBattleflyTreasuryFlywheelVault public TREASURY_VAULT;

    uint256 public activeDepositId;
    uint256 public activeRestakeDepositId;
    uint256 public pendingStakeBackAmount;
    address public BattleflyBot;

    event WithdrawalFromStaker(uint256 depositId);
    event RequestWithdrawalFromStaker(uint256 depositId);

    // Upgrade Atlas Staker End

    IBattleflyHarvesterEmissions public BattleflyHarvesterEmissions;

    address public OPEX;

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

        require(stakeBackPercent + treasuryPercent + v2VaultPercent <= PERCENT_DENOMINATOR);

        // Approve the AtlasStaker contract to spend the magic
        magic.safeApprove(address(BattleflyStaker), 2**256 - 1);
    }

    // ============================================ USER OPERATIONS ==============================================

    /**
     * @dev Claim past emissions for all owned founders tokens
     */
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

    /**
     * @dev get all tokens eligible for cliaming past emissions
     */
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

    /**
     * @dev set founder tokens that can claim past emissions
     */
    function setTokenClaimedPastEmission(uint256[] memory tokenIds, bool isClaimed) external onlyOwner {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            claimedPastEmission[tokenIds[i]] = isClaimed;
        }
    }

    /**
     * @dev set the amount of past emissions per founder token
     */
    function setPastEmission(uint256 amount) external onlyOwner {
        pastEmissionPerFounder = amount;
    }

    /**
     * @dev returns the stake objects and the corresponding founder tokens in the stakes of a specific owner
     */
    function stakesOf(address owner) public view returns (FounderStake[] memory, uint256[][] memory) {
        FounderStake[] memory stakes = new FounderStake[](FounderStakeOfOwner[owner].length());
        uint256[][] memory _founderIDsOfStake = new uint256[][](FounderStakeOfOwner[owner].length());
        for (uint256 i = 0; i < FounderStakeOfOwner[owner].length(); i++) {
            stakes[i] = FounderStakes[FounderStakeOfOwner[owner].at(i)];
            _founderIDsOfStake[i] = stakingFounderOfStakeId[FounderStakeOfOwner[owner].at(i)].values();
        }
        return (stakes, _founderIDsOfStake);
    }

    function isOwner(address owner, uint256 tokenId) public view returns (bool) {
        (, uint256[][] memory tokensPerStake) = stakesOf(owner);
        for (uint256 i = 0; i < tokensPerStake.length; i++) {
            for (uint256 j = 0; j < tokensPerStake[i].length; j++) {
                if (tokensPerStake[i][j] == tokenId) {
                    return true;
                }
            }
        }
        return false;
    }

    /**
     * @dev Returns the founder tokens balance of an owner
     */
    function balanceOf(address owner) external view returns (uint256 balance) {
        require(owner != address(0), "ERC721: balance query for the zero address");

        uint256 balanceOfUser = 0;
        uint256 founderStakeCount = FounderStakeOfOwner[owner].length();

        for (uint256 i = 0; i < founderStakeCount; i++) {
            balanceOfUser += FounderStakes[FounderStakeOfOwner[owner].at(i)].amount;
        }

        return balanceOfUser;
    }

    /**
     * @dev Stake a list of founder tokens
     */
    function stakeFounderNFT(uint256[] memory ids) external {
        require(ids.length != 0, "Must provide at least one founder NFT ID");
        for (uint256 i = 0; i < ids.length; i++) {
            require(founderNFT.getSpecialNFTType(ids[i]) == founderTypeID, "Not valid founder NFT");
            founderNFT.safeTransferFrom(msg.sender, address(this), ids[i]);
        }
        uint256 currentDay = DaysSinceStart;
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

    /**
     * @dev Indicates if claiming is paused
     */
    function isPaused() external view returns (bool) {
        return claimingIsPaused;
    }

    /**
     * @dev Claim all emissions for the founder tokens owned by the sender
     */
    function claimAll() external nonReentrant {
        if (claimingIsPaused) {
            revert("Claiming is currently paused, please try again later");
        }

        uint256 totalReward = 0;

        for (uint256 i = 0; i < FounderStakeOfOwner[msg.sender].length(); i++) {
            totalReward += _claimByStakeId(FounderStakeOfOwner[msg.sender].at(i));
        }

        require(totalReward > 0, "No reward to claim");
    }

    /**
     * @dev Withdraw all founder tokens of the sender
     */
    function withdrawAll() external nonReentrant {
        require(FounderStakeOfOwner[msg.sender].length() > 0, "No STAKE to withdraw");
        uint256 totalWithdraw = 0;
        uint256[] memory stakeIds = FounderStakeOfOwner[msg.sender].values();
        for (uint256 i = 0; i < stakeIds.length; i++) {
            uint256 stakeId = stakeIds[i];
            _claimByStakeId(stakeId);
            totalWithdraw += FounderStakes[stakeId].amount;
            _withdrawByStakeId(stakeId);
        }
        _checkStakingAmount(totalWithdraw);
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

    /**
     * @dev Withdraw a list of founder tokens
     */
    function withdraw(uint256[] memory founderIds) external nonReentrant {
        require(founderIds.length > 0, "No Founder to withdraw");
        _checkStakingAmount(founderIds.length);
        for (uint256 i = 0; i < founderIds.length; i++) {
            uint256 stakeId = stakeIdOfFounder[founderIds[i]];
            require(FounderStakes[stakeId].owner == msg.sender, "Not your stake");
            _claimBeforeWithdraw(founderIds[i]);
            _withdraw(founderIds[i]);
        }
    }

    function _checkStakingAmount(uint256 totalWithdraw) internal view {
        uint256 stakeableAmountPerFounder = founderTypeID == 150
            ? BattleflyFoundersFlywheelVault.STAKING_LIMIT_V1()
            : BattleflyFoundersFlywheelVault.STAKING_LIMIT_V2();
        uint256 currentlyRemaining = BattleflyFoundersFlywheelVault.remainingStakeableAmount(msg.sender);
        uint256 currentlyStaked = BattleflyFoundersFlywheelVault.getStakedAmount(msg.sender);
        uint256 remainingAfterSubstraction = currentlyRemaining +
            currentlyStaked -
            (stakeableAmountPerFounder * totalWithdraw);
        require(currentlyStaked <= remainingAfterSubstraction, "Pls withdraw from FlywheelVault first");
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

    /**
     * @dev Get the emissions claimable by a certain user
     */
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

    function _depositToStaker(uint256 amount, IAtlasMine.Lock lock) internal returns (uint256 depositId) {
        depositId = BattleflyStakerV2.deposit(amount, lock);
        depositIds.add(depositId);
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

    function _claimAllFromStaker() private returns (uint256 amount) {
        uint256[] memory ids = depositIds.values();
        for (uint256 i = 0; i < ids.length; i++) {
            (uint256 pending, ) = BattleflyStakerV2.getClaimableEmission(ids[i]);
            if (pending > 0) {
                amount += BattleflyStakerV2.claim(ids[i]);
            }
        }
        amount += BattleflyHarvesterEmissions.claim(address(this));
    }

    function _stakeBack(uint256 stakeBackAmount) internal {
        pendingStakeBackAmount += stakeBackAmount;
        if (activeRestakeDepositId == 0 && pendingStakeBackAmount > 0) {
            activeRestakeDepositId = _depositToStaker(pendingStakeBackAmount, DEFAULT_STAKE_BACK_LOCK);
            pendingStakeBackAmount = 0;
        } else if (activeRestakeDepositId > 0 && BattleflyStakerV2.canWithdraw(activeRestakeDepositId)) {
            uint256 withdrawn = BattleflyStakerV2.withdraw(activeRestakeDepositId);
            depositIds.remove(activeRestakeDepositId);
            uint256 toDeposit = withdrawn + pendingStakeBackAmount;
            activeRestakeDepositId = _depositToStaker(toDeposit, DEFAULT_STAKE_BACK_LOCK);
            depositIds.add(activeRestakeDepositId);
            pendingStakeBackAmount = 0;
        } else if (activeRestakeDepositId > 0 && BattleflyStakerV2.canRequestWithdrawal(activeRestakeDepositId)) {
            BattleflyStakerV2.requestWithdrawal(activeRestakeDepositId);
        }
        pendingFounderEmission = 0;
    }

    /**
     * @dev Return the name of the vault
     */
    function getName() public view returns (string memory) {
        if (founderTypeID == 150) {
            return "V1 Stakers Vault";
        } else {
            return "V2 Stakers Vault";
        }
    }

    // ============================================ ADMIN OPERATIONS ==============================================

    /**
     * @dev Topup magic directly to the atlas staker
     */
    function topupMagicToStaker(uint256 amount, IAtlasMine.Lock lock) external onlyAdminAccess {
        require(amount > 0);
        magic.safeTransferFrom(msg.sender, address(this), amount);
        _depositToStaker(amount, lock);
        emit TopupMagicToStaker(msg.sender, amount, lock);
    }

    /**
     * @dev Topup magic to be staked in the daily emission batch
     */
    function topupTodayEmission(uint256 amount) external onlyAdminAccess {
        require(amount > 0);
        magic.safeTransferFrom(msg.sender, address(this), amount);
        pendingFounderEmission += amount;
        emit TopupTodayEmission(msg.sender, amount);
    }

    // to support initial staking period, only to be run after staking period is over
    function setFounderStakesToStart() public onlyAdminAccess nonReentrant {
        uint256 length = lastStakeId;

        for (uint256 i = 0; i <= length; i++) {
            FounderStakes[i].stakeTimestamp = startTimestamp;
            FounderStakes[i].lastClaimedDay = 0;
        }
    }

    /**
     * @dev Update the claimed founder emission for a certain day
     */
    function updateClaimedFounderEmission(uint256 amount, uint256 currentDay) external onlyAdminAccess {
        DaysSinceStart = currentDay;
        uint256 todayTotalFounderNFTs = _updateTotalStakingFounders(currentDay);
        DailyFounderEmissions[DaysSinceStart] = DailyFounderEmission({
            totalEmission: amount,
            totalFounders: todayTotalFounderNFTs
        });
    }

    /**
     * @dev Get the current day
     */
    function getCurrentDay() public view onlyAdminAccess returns (uint256) {
        return DaysSinceStart;
    }

    /**
     * @dev Get the daily founder emission for a specific day
     */
    function getDailyFounderEmission(uint256 currentDay) public view onlyAdminAccess returns (uint256[2] memory) {
        return [DailyFounderEmissions[currentDay].totalEmission, DailyFounderEmissions[currentDay].totalFounders];
    }

    /**
     * @dev set the start timestamp
     */
    function setStartTimestamp(uint256 newTimestamp) public onlyAdminAccess {
        startTimestamp = newTimestamp;
    }

    /**
     * @dev Simulate a claim for a specific token id
     */
    function simulateClaim(uint256 tokenId) public view onlyAdminAccess returns (uint256) {
        uint256 stakeId = stakeIdOfFounder[tokenId];
        return _getClaimableEmissionOf(stakeId);
    }

    /**
     * @dev Pause or unpause claiming
     */
    function pauseClaim(bool doPause) external onlyAdminAccess {
        claimingIsPaused = doPause;
    }

    /**
     * @dev Reduce the total emission
     */
    function reduceTotalEmission(uint256 amount) external onlyAdminAccess {
        totalEmission -= amount;
    }

    /**
     * @dev Increase the total emission
     */
    function increaseTotalEmission(uint256 amount) external onlyAdminAccess {
        totalEmission += amount;
    }

    /**
     * @dev Recalculate the total amount of founders to be included for every day starting from a specific day
     */
    function recalculateTotalFounders(uint256 dayToStart) external onlyAdminAccess {
        uint256 base = DailyFounderEmissions[dayToStart].totalFounders;

        for (uint256 index = dayToStart + 1; index <= DaysSinceStart; index++) {
            DailyFounderEmission storage daily = DailyFounderEmissions[index];

            daily.totalFounders += base;
        }
    }

    /**
     * @dev Claim daily emissions from AtlasStaker and distribute over founder token stakers
     */
    function claimDailyEmission() public onlyBattleflyBot nonReentrant {
        uint256 currentDay = DaysSinceStart + 1;

        uint256 todayTotalEmission = _claimAllFromStaker();

        uint256 todayTotalFounderNFTs = _updateTotalStakingFounders(currentDay);

        uint256 stakeBackAmount;
        uint256 v2VaultAmount;
        uint256 treasuryAmount;
        uint256 founderEmission;
        if (todayTotalEmission != 0) {
            stakeBackAmount = ((todayTotalEmission * stakeBackPercent) / PERCENT_DENOMINATOR);
            _stakeBack(stakeBackAmount + pendingFounderEmission);

            v2VaultAmount = (todayTotalEmission * v2VaultPercent) / PERCENT_DENOMINATOR;
            if (v2VaultAmount != 0) {
                magic.approve(address(battleflyFounderVaultV2), v2VaultAmount);
                battleflyFounderVaultV2.topupTodayEmission(v2VaultAmount);
            }

            treasuryAmount = (todayTotalEmission * treasuryPercent) / PERCENT_DENOMINATOR;
            if (treasuryAmount != 0) {
                uint256 opexAmount = (treasuryAmount * 9500) / PERCENT_DENOMINATOR;
                uint256 v2Amount = (treasuryAmount * 500) / PERCENT_DENOMINATOR;
                magic.safeTransfer(OPEX, opexAmount);
                magic.approve(address(battleflyFounderVaultV2), v2Amount);
                battleflyFounderVaultV2.topupTodayEmission(v2Amount);
            }
            founderEmission += todayTotalEmission - stakeBackAmount - v2VaultAmount - treasuryAmount;
        } else if (pendingFounderEmission > 0) {
            _stakeBack(pendingFounderEmission);
        } else {
            _stakeBack(0);
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

    /**
     * @dev Withdraw all withdrawable deposit ids from the vault in the Atlas Staker
     */
    function withdrawAllFromStaker() external onlyAdminAccess {
        uint256[] memory ids = depositIds.values();
        withdrawFromStaker(ids);
    }

    function withdrawFromStaker(uint256[] memory ids) public onlyAdminAccess {
        claimDailyEmission();
        require(ids.length > 0, "BattleflyFlywheelVault: No deposited funds");
        for (uint256 i = 0; i < ids.length; i++) {
            if (BattleflyStakerV2.canWithdraw(ids[i])) {
                BattleflyStakerV2.withdraw(ids[i]);
                depositIds.remove(ids[i]);
                emit WithdrawalFromStaker(ids[i]);
            }
        }
    }

    /**
     * @dev Request a withdrawal from Atlas Staker for all claimable deposit ids
     */
    function requestWithdrawAllFromStaker() external onlyAdminAccess {
        uint256[] memory ids = depositIds.values();
        requestWithdrawFromStaker(ids);
    }

    /**
     * @dev Request a withdrawal from Atlas Staker for specific deposit ids
     */
    function requestWithdrawFromStaker(uint256[] memory ids) public onlyAdminAccess {
        for (uint256 i = 0; i < ids.length; i++) {
            if (BattleflyStakerV2.canRequestWithdrawal(ids[i])) {
                BattleflyStakerV2.requestWithdrawal(ids[i]);
                emit RequestWithdrawalFromStaker(ids[i]);
            }
        }
    }

    function setDaysSinceStart(uint256 daysSince) public onlyAdminAccess {
        DaysSinceStart = daysSince;
    }

    /**
     * @dev Withdraw a specific magic amount from the vault and send it to a receiver
     */
    function withdrawFromVault(address receiver, uint256 amount) external onlyAdminAccess {
        magic.safeTransfer(receiver, amount);
    }

    /**
     * @dev Set the daily founder emissions for a specific day
     */
    function setDailyFounderEmissions(
        uint256 day,
        uint256 amount,
        uint256 stakers
    ) external onlyAdminAccess {
        DailyFounderEmissions[day] = DailyFounderEmission(amount, stakers);
    }

    /**
     * @dev Set the treasury vault address
     */
    function setTreasuryVault(address _treasuryAddress) external onlyAdminAccess {
        require(_treasuryAddress != address(0));
        TREASURY_VAULT = IBattleflyTreasuryFlywheelVault(_treasuryAddress);
    }

    //Must be called right after init
    /**
     * @dev Set the flywheel vault address
     */
    function setFlywheelVault(address vault) external onlyOwner {
        require(vault != address(0));
        BattleflyFoundersFlywheelVault = IBattleflyFoundersFlywheelVault(vault);
    }

    //Must be called right after init
    /**
     * @dev Set the battlefly bot address
     */
    function setBattleflyBot(address _battleflyBot) external onlyOwner {
        require(_battleflyBot != address(0));
        BattleflyBot = _battleflyBot;
    }

    //Must be called right after init
    /**
     * @dev Set the battlefly staker address
     */
    function setBattleflyStaker(address staker) external onlyOwner {
        require(staker != address(0));
        BattleflyStakerV2 = IBattleflyAtlasStakerV02(staker);
        // Approve the AtlasStaker contract to spend the magic
        magic.approve(address(BattleflyStakerV2), 2**256 - 1);
    }

    //Must be called right after init
    /**
     * @dev Set the founder vault address
     */
    function setFounderVaultV2(address founderVault) external onlyOwner {
        require(founderVault != address(0));
        battleflyFounderVaultV2 = IBattleflyFounderVault(founderVault);
        // Approve the FounderVault contract to spend the magic
        magic.approve(address(battleflyFounderVaultV2), 2**256 - 1);
    }

    /**
     * @dev Set the harvester emissions contract
     */
    function setHarvesterEmission(address _harvesterEmission) external onlyOwner {
        require(_harvesterEmission != address(0));
        BattleflyHarvesterEmissions = IBattleflyHarvesterEmissions(_harvesterEmission);
    }

    /**
     * @dev Set the OPEX address
     */
    function setOpex(address _opex) external onlyOwner {
        require(_opex != address(0));
        OPEX = _opex;
    }

    //Must be called right after init
    /**
     * @dev Set the distribution percentages
     */
    function setPercentages(
        uint256 _stakeBackPercent,
        uint256 _treasuryPercent,
        uint256 _v2VaultPercent
    ) external onlyOwner {
        require(_stakeBackPercent + _treasuryPercent + _v2VaultPercent <= PERCENT_DENOMINATOR);
        stakeBackPercent = _stakeBackPercent;
        treasuryPercent = _treasuryPercent;
        v2VaultPercent = _v2VaultPercent;
    }

    /**
     * @dev Set admin access for a specific user
     */
    function setAdminAccess(address user, bool access) external onlyOwner {
        adminAccess[user] = access;
    }

    modifier onlyAdminAccess() {
        require(adminAccess[_msgSender()] || _msgSender() == owner(), "Require admin access");
        _;
    }

    modifier onlyBattleflyBot() {
        require(msg.sender == BattleflyBot, "Require battlefly bot");
        _;
    }
}

