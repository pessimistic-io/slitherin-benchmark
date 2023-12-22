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

import "./IAtlasMine.sol";
import "./IBattleflyAtlasStakerV02.sol";
import "./IVault.sol";
import "./BattleflyAtlasStakerUtils.sol";
import "./IBattleflyTreasuryFlywheelVault.sol";
import "./IBattleflyHarvesterEmissions.sol";
import "./IFlywheelEmissions.sol";

/// @custom:oz-upgrades-unsafe-allow external-library-linking
contract BattleflyAtlasStakerV02 is
    IBattleflyAtlasStakerV02,
    Initializable,
    OwnableUpgradeable,
    ERC1155HolderUpgradeable,
    ERC721HolderUpgradeable,
    ReentrancyGuardUpgradeable
{
    using AddressUpgradeable for address;
    using SafeCastUpgradeable for uint256;
    using SafeCastUpgradeable for int256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    // ========== CONSTANTS ==========

    uint96 public constant override FEE_DENOMINATOR = 10000;
    uint256 public constant ONE = 1e28;
    address public BATTLEFLY_BOT;

    IERC20Upgradeable public override MAGIC;
    IAtlasMine public ATLAS_MINE;
    IBattleflyTreasuryFlywheelVault public TREASURY_VAULT;

    IAtlasMine.Lock[] public LOCKS;
    IAtlasMine.Lock[] public allowedLocks;

    // ========== Operator States ==========
    uint256 public override currentDepositId;
    uint64 public override currentEpoch;
    uint256 public override pausedUntil;
    uint256 public nextExecution;

    /**
     * @dev active positionIds in AtlasMine for this contract.
     *
     */
    EnumerableSetUpgradeable.UintSet private activePositionIds;

    /**
     * @dev Total emissions harvested from Atlas Mine for a particular lock period and epoch
     *      { lock } => { epoch } => { emissions }
     */
    mapping(IAtlasMine.Lock => mapping(uint64 => uint256)) public totalEmissionsAtEpochForLock;

    /**
     * @dev Total amount of magic staked in Atlas Mine for a particular lock period and epoch
     *      { lock } => { epoch } => { magic }
     */
    mapping(IAtlasMine.Lock => mapping(uint64 => uint256)) public override totalStakedAtEpochForLock;

    /**
     * @dev Total amount of emissions per share in magic for a particular lock period and epoch
     *      { lock } => { epoch } => { emissionsPerShare }
     */
    mapping(IAtlasMine.Lock => mapping(uint64 => uint256)) public override totalPerShareAtEpochForLock;

    /**
     * @dev Total amount of unstaked Magic at a particular epoch
     *      { epoch } => { unstaked magic }
     */
    mapping(uint64 => uint256) public unstakeAmountAtEpoch;

    /**
     * @dev Legion ERC721 NFT stakers data
     *      { tokenId } => { depositor }
     */
    mapping(uint256 => address) public legionStakers;

    /**
     * @dev TREASURE ERC1155 NFT stakers data
     *      { tokenId } => { depositor } => { deposit amount }
     */
    mapping(uint256 => mapping(address => uint256)) public treasureStakers;

    /**
     * @dev Vaultstakes per depositId
     *      { depositId } => { VaultStake }
     */
    mapping(uint256 => VaultStake) public vaultStakes;

    /**
     * @dev Vaults' all deposits
     *      { address } => { depositId }
     */
    mapping(address => EnumerableSetUpgradeable.UintSet) private depositIdByVault;

    /**
     * @dev Magic amount that is not staked to AtlasMine
     *      { Lock } => { unstaked amount }
     */
    mapping(IAtlasMine.Lock => uint256) public unstakedAmount;

    // ========== Access Control States ==========
    mapping(address => bool) public superAdmins;

    /**
     * @dev Whitelisted vaults
     *      { vault address } => { Vault }
     */
    mapping(address => Vault) public vaults;

    // ========== CONTRACT UPGRADE FOR BATCHED HARVESTING (ArbGas limit) ======= //

    uint256 public accruedEpochEmission;
    EnumerableSetUpgradeable.UintSet private atlasPositionsToRemove;

    // ========== CONTRACT UPGRADE FOR HARVESTER EMISSIONS ======= //

    IBattleflyHarvesterEmissions public HARVESTER_EMISSION;

    // ========== CONTRACT UPGRADE FOR GFLY DYNAMICS ======= //

    uint64 public override transitionEpoch;
    IFlywheelEmissions public FLYWHEEL_EMISSIONS;

    // ========== CONTRACT UPGRADE FOR FLYWHEEL 3.0 MIGRATION ======= //

    uint256 public withdrawnForMigration;
    uint256 public constant TOTAL_MAGIC_FOR_MIGRATION = 3178561320000000000000000;

    // ========== CONTRACT UPGRADE FOR FLYWHEEL 3.0 MIGRATION 2.0 ======= //

    uint256 public withdrawnForMigration2;
    uint256 public constant TOTAL_MAGIC_FOR_MIGRATION_2 = 257000000000000000000000;

    // Disable initializer to save contract space

    /* function initialize(
        address _magic,
        address _atlasMine,
        address _treasury,
        address _battleflyBot,
        IAtlasMine.Lock[] memory _allowedLocks
    ) external initializer {
        __ERC1155Holder_init();
        __ERC721Holder_init();
        __Ownable_init();
        __ReentrancyGuard_init();

        require(_magic != address(0), "BattleflyAtlasStaker: invalid address");
        require(_atlasMine != address(0), "BattleflyAtlasStaker: invalid address");
        MAGIC = IERC20Upgradeable(_magic);
        ATLAS_MINE = IAtlasMine(_atlasMine);

        superAdmins[msg.sender] = true;
        LOCKS = [
            IAtlasMine.Lock.twoWeeks,
            IAtlasMine.Lock.oneMonth,
            IAtlasMine.Lock.threeMonths,
            IAtlasMine.Lock.sixMonths,
            IAtlasMine.Lock.twelveMonths
        ];

        nextExecution = block.timestamp;

        setTreasury(_treasury);
        setBattleflyBot(_battleflyBot);
        setAllowedLocks(_allowedLocks);

        approveLegion(true);
        approveTreasure(true);
    }*/

    // ============================== Vault Operations ==============================

    /**
     * @dev deposit an amount of MAGIC in the AtlasStaker for a particular lock period
     */
    function deposit(
        uint256 _amount,
        IAtlasMine.Lock _lock
    ) external override onlyWhitelistedVaults nonReentrant whenNotPaused onlyAvailableLock(_lock) returns (uint256) {
        require(_amount > 0, "BattflyAtlasStaker: cannot deposit 0");
        // Transfer MAGIC from Vault
        MAGIC.safeTransferFrom(msg.sender, address(this), _amount);

        uint256 newDepositId = ++currentDepositId;
        _deposit(newDepositId, _amount, _lock);
        return newDepositId;
    }

    /**
     * @dev withdraw a vaultstake from the AtlasStaker with a specific depositId
     */
    function withdraw(uint256 _depositId) public override nonReentrant whenNotPaused returns (uint256 amount) {
        VaultStake memory vaultStake = vaultStakes[_depositId];
        require(vaultStake.vault == msg.sender, "BattleflyAtlasStaker: caller is not a correct vault");
        // withdraw can only happen if the retention period has passed.
        require(canWithdraw(_depositId), "BattleflyAtlasStaker: position is locked");

        amount = vaultStake.amount;
        // Withdraw MAGIC to user
        MAGIC.safeTransfer(msg.sender, amount);

        // claim remaining emissions
        (uint256 emission, ) = getClaimableEmission(_depositId);
        if (emission > 0) {
            amount += _claim(_depositId);
        }

        // Reset vault stake data
        delete vaultStakes[_depositId];
        depositIdByVault[msg.sender].remove(_depositId);
        emit WithdrawPosition(msg.sender, amount, _depositId);
    }

    /**
     * @dev Claim emissions from a vaultstake in the AtlasStaker with a specific depositId
     */
    function claim(uint256 _depositId) public override nonReentrant whenNotPaused returns (uint256 amount) {
        amount = _claim(_depositId);
    }

    /**
     * @dev Request a withdrawal for a specific depositId. This is required because the vaultStake will be restaked in blocks of 2 weeks after the unlock period has passed.
     * This function is used to notify the AtlasStaker that it should not restake the vaultStake on the next iteration and the initial stake becomes unlocked.
     */
    function requestWithdrawal(uint256 _depositId) public override nonReentrant whenNotPaused returns (uint64) {
        VaultStake storage vaultStake = vaultStakes[_depositId];
        require(vaultStake.vault == msg.sender, "BattleflyAtlasStaker: caller is not a correct vault");
        require(vaultStake.retentionUnlock == 0, "BattleflyAtlasStaker: withdrawal already requested");
        // Every epoch is 1 day; We can start requesting for a withdrawal 14 days before the unlock period.
        require(currentEpoch >= (vaultStake.unlockAt - 14), "BattleflyAtlasStaker: position not yet unlockable");

        // We set the retention period before the withdrawal can happen to the nearest epoch in the future
        uint64 retentionUnlock = currentEpoch < vaultStake.unlockAt
            ? vaultStake.unlockAt
            : currentEpoch + (14 - ((currentEpoch - vaultStake.unlockAt) % 14));
        vaultStake.retentionUnlock = retentionUnlock - 1 == currentEpoch ? retentionUnlock + 14 : retentionUnlock;
        unstakeAmountAtEpoch[vaultStake.retentionUnlock - 1] += vaultStake.amount;
        emit RequestWithdrawal(msg.sender, vaultStake.retentionUnlock, _depositId);
        return vaultStake.retentionUnlock;
    }

    // ============================== Super Admin Operations ==============================

    /**
     * @dev Execute the daily cron job to deposit funds to AtlasMine & claim emissions from AtlasMine
     *      The Battlefly CRON BOT will use this function to execute deposit/claim.
     */
    function startHarvestAndDistribute() external onlyBattleflyBot {
        //require(block.timestamp >= nextExecution, "BattleflyAtlasStaker: Executed less than 24h ago");
        // set to 24 hours - 5 minutes to take blockchain tx delays into account.
        nextExecution = block.timestamp + 86100;
        accruedEpochEmission = 0;
    }

    /**
     * @dev Execute the daily cron job to harvest all emissions from AtlasMine
     */
    function executeHarvestAll(uint256 _position, uint256 _batchSize) external onlyBattleflyBot {
        uint256 endPosition = activePositionIds.length() < (_position + _batchSize)
            ? activePositionIds.length()
            : (_position + _batchSize);
        uint256 pendingHarvest = _updateEmissionsForEpoch(_position, endPosition);
        uint256 preHarvest = MAGIC.balanceOf(address(this));
        for (uint256 i = _position; i < endPosition; i++) {
            ATLAS_MINE.harvestPosition(activePositionIds.at(i));
        }
        uint256 harvested = MAGIC.balanceOf(address(this)) - preHarvest;
        require(pendingHarvest == harvested, "BattleflyAtlasStaker: pending harvest and actual harvest are not equal");
        if (currentEpoch >= transitionEpoch) {
            MAGIC.safeApprove(address(FLYWHEEL_EMISSIONS), harvested);
            FLYWHEEL_EMISSIONS.topupFlywheelEmissions(harvested);
        }
    }

    /**
     * @dev Execute the daily cron job to update emissions
     */
    function executeUpdateEmissions() external onlyBattleflyBot {
        // Calculate the accrued emissions per share by (accruedEmissionForLock * 1e18) / totalStaked
        // Set the total emissions to the accrued emissions of the current epoch + the previous epochs
        for (uint256 k = 0; k < LOCKS.length; k++) {
            uint256 totalStaked = totalStakedAtEpochForLock[LOCKS[k]][currentEpoch];
            if (totalStaked > 0 && currentEpoch < transitionEpoch) {
                uint256 accruedEmissionForLock = currentEpoch > 0
                    ? totalEmissionsAtEpochForLock[LOCKS[k]][currentEpoch] -
                        totalEmissionsAtEpochForLock[LOCKS[k]][currentEpoch - 1]
                    : 0;
                uint256 accruedRewardsPerShare = (accruedEmissionForLock * ONE) / totalStaked;
                totalPerShareAtEpochForLock[LOCKS[k]][currentEpoch] = currentEpoch > 0
                    ? totalPerShareAtEpochForLock[LOCKS[k]][currentEpoch - 1] + accruedRewardsPerShare
                    : accruedRewardsPerShare;
            } else {
                totalPerShareAtEpochForLock[LOCKS[k]][currentEpoch] = currentEpoch > 0
                    ? totalPerShareAtEpochForLock[LOCKS[k]][currentEpoch - 1]
                    : 0;
            }
        }
    }

    /**
     * @dev Execute the daily cron job to withdraw all positions from AtlasMine
     */
    function executeWithdrawAll(uint256 _position, uint256 _batchSize) external onlyBattleflyBot {
        uint256[] memory depositIds = activePositionIds.values();
        uint256 endPosition = depositIds.length < (_position + _batchSize)
            ? depositIds.length
            : (_position + _batchSize);
        for (uint256 i = _position; i < endPosition; i++) {
            (uint256 amount, , , uint256 lockedUntil, , , IAtlasMine.Lock lock) = ATLAS_MINE.userInfo(
                address(this),
                depositIds[i]
            );
            uint256 totalLockedPeriod = lockedUntil + ATLAS_MINE.getVestingTime(lock);

            // If the position is available to withdraw
            if (totalLockedPeriod <= block.timestamp) {
                ATLAS_MINE.withdrawPosition(depositIds[i], type(uint256).max);
                atlasPositionsToRemove.add(depositIds[i]);
                // Directly register for restaking, unless a withdrawal is requested (we correct this in executeDepositAll())
                unstakedAmount[IAtlasMine.Lock.twoWeeks] += uint256(amount);
            }
        }
    }

    /**
     * @dev Execute the daily cron job to deposit all to AtlasMine
     */
    function executeDepositAll() external onlyBattleflyBot {
        // Increment the epoch
        currentEpoch++;
        // Possibly correct the amount to be deposited due to users withdrawing their stake.
        if (unstakedAmount[IAtlasMine.Lock.twoWeeks] >= unstakeAmountAtEpoch[currentEpoch]) {
            unstakedAmount[IAtlasMine.Lock.twoWeeks] -= unstakeAmountAtEpoch[currentEpoch];
        } else {
            //If not enough withdrawals available from current epoch, request more from the next epoch
            unstakeAmountAtEpoch[currentEpoch + 1] += (unstakeAmountAtEpoch[currentEpoch] -
                unstakedAmount[IAtlasMine.Lock.twoWeeks]);
            unstakedAmount[IAtlasMine.Lock.twoWeeks] = 0;
        }

        uint256 unstaked;
        // Disable deposits to AtlasMine to get everything liquid to migrate to flywheel 3.0
        /*  for (uint256 i = 0; i < LOCKS.length; i++) {
            uint256 amount = unstakedAmount[LOCKS[i]];
            if (amount > 0) {
                unstaked += amount;
                MAGIC.safeApprove(address(ATLAS_MINE), amount);
                ATLAS_MINE.deposit(amount, LOCKS[i]);
                activePositionIds.add(ATLAS_MINE.currentId(address(this)));
                unstakedAmount[LOCKS[i]] = 0;
            }
        }*/
        emit DepositedAllToMine(unstaked);
    }

    /**
     * @dev Finish the daily cron job to deposit funds to AtlasMine & claim emissions from AtlasMine
     *      The Battlefly CRON BOT will use this function to execute deposit/claim.
     */
    function finishHarvestAndDistribute() external onlyBattleflyBot {
        uint256[] memory toRemove = atlasPositionsToRemove.values();
        for (uint256 i = 0; i < toRemove.length; i++) {
            activePositionIds.remove(toRemove[i]);
            atlasPositionsToRemove.remove(toRemove[i]);
        }
    }

    /**
     * @dev
     * Withdraw the liquid amount for the migration once available and transfer to owner (from where it will be distributed)
     */
    function withdrawLiquidAmountForMigration(uint256 amount) external override onlyOwner {
        require(unstakedAmount[IAtlasMine.Lock.twoWeeks] >= amount, "BattleflyAtlasStaker: Not enough liquid amount");
        require(
            amount + withdrawnForMigration2 <= TOTAL_MAGIC_FOR_MIGRATION_2,
            "BattleflyAtlasStaker: Amount execeeds amount withdrawable for migration"
        );
        withdrawnForMigration2 += amount;
        unstakedAmount[IAtlasMine.Lock.twoWeeks] -= amount;
        MAGIC.safeTransfer(msg.sender, amount);
    }

    /**
     * @dev
     * Deposit liquid amount of magic into this contract.
     */
    function depositLiquidAmount(uint256 amount) external override {
        unstakedAmount[IAtlasMine.Lock.twoWeeks] += amount;
        MAGIC.safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @dev Approve TREASURE ERC1155 NFT transfer to deposit into AtlasMine contract
     */
    function approveTreasure(bool _approve) public onlySuperAdmin {
        getTREASURE().setApprovalForAll(address(ATLAS_MINE), _approve);
    }

    /**
     * @dev Approve LEGION ERC721 NFT transfer to deposit into AtlasMine contract
     */
    function approveLegion(bool _approve) public onlySuperAdmin {
        getLEGION().setApprovalForAll(address(ATLAS_MINE), _approve);
    }

    /**
     * @dev Stake TREASURE ERC1155 NFT
     */
    /*function stakeTreasure(uint256 _tokenId, uint256 _amount) external onlySuperAdmin nonReentrant {
        require(_amount > 0, "BattleflyAtlasStaker: Invalid TREASURE amount");

        // Caller's balance check already implemented in _safeTransferFrom() in ERC1155Upgradeable contract
        getTREASURE().safeTransferFrom(msg.sender, address(this), _tokenId, _amount, "");
        treasureStakers[_tokenId][msg.sender] += _amount;

        // Token Approval is already done in constructor
        ATLAS_MINE.stakeTreasure(_tokenId, _amount);
        emit StakedTreasure(msg.sender, _tokenId, _amount);
    }*/

    /**
     * @dev Unstake TREASURE ERC1155 NFT
     */
    function unstakeTreasure(uint256 _tokenId, uint256 _amount) external onlySuperAdmin nonReentrant {
        require(_amount > 0, "BattleflyAtlasStaker: Invalid TREASURE amount");
        require(treasureStakers[_tokenId][msg.sender] >= _amount, "BattleflyAtlasStaker: Invalid TREASURE amount");
        // Unstake TREASURE from AtlasMine
        ATLAS_MINE.unstakeTreasure(_tokenId, _amount);

        // Transfer TREASURE to the staker
        getTREASURE().safeTransferFrom(address(this), msg.sender, _tokenId, _amount, "");
        treasureStakers[_tokenId][msg.sender] -= _amount;
        emit UnstakedTreasure(msg.sender, _tokenId, _amount);
    }

    /**
     * @dev Stake LEGION ERC721 NFT
     */
    /*  function stakeLegion(uint256 _tokenId) external onlySuperAdmin nonReentrant {
        // TokenId ownership validation is already implemented in safeTransferFrom function
        getLEGION().safeTransferFrom(msg.sender, address(this), _tokenId, "");
        legionStakers[_tokenId] = msg.sender;

        // Token Approval is already done in constructor
        ATLAS_MINE.stakeLegion(_tokenId);
        emit StakedLegion(msg.sender, _tokenId);
    }*/

    /**
     * @dev Unstake LEGION ERC721 NFT
     */
    function unstakeLegion(uint256 _tokenId) external onlySuperAdmin nonReentrant {
        require(legionStakers[_tokenId] == msg.sender, "BattleflyAtlasStaker: Invalid staker");
        // Unstake LEGION from AtlasMine
        ATLAS_MINE.unstakeLegion(_tokenId);

        // Transfer LEGION to the staker
        getLEGION().safeTransferFrom(address(this), msg.sender, _tokenId, "");
        legionStakers[_tokenId] = address(0);
        emit UnstakedLegion(msg.sender, _tokenId);
    }

    // ============================== Owner Operations ==============================

    /**
     * @dev Add super admin permission
     */
    function addSuperAdmin(address _admin) public onlyOwner {
        require(!superAdmins[_admin], "BattleflyAtlasStaker: admin already exists");
        superAdmins[_admin] = true;
        emit AddedSuperAdmin(_admin);
    }

    /**
     * @dev Batch adding super admin permission
     */
    function addSuperAdmins(address[] calldata _admins) external onlyOwner {
        for (uint256 i = 0; i < _admins.length; i++) {
            addSuperAdmin(_admins[i]);
        }
    }

    /**
     * @dev Remove super admin permission
     */
    function removeSuperAdmin(address _admin) public onlyOwner {
        require(superAdmins[_admin], "BattleflyAtlasStaker: admin does not exist");
        superAdmins[_admin] = false;
        emit RemovedSuperAdmin(_admin);
    }

    /**
     * @dev Batch removing super admin permission
     */
    function removeSuperAdmins(address[] calldata _admins) external onlyOwner {
        for (uint256 i = 0; i < _admins.length; i++) {
            removeSuperAdmin(_admins[i]);
        }
    }

    /**
     * @dev Add vault address
     */
    function addVault(address _vault, Vault calldata _vaultData) public onlyOwner {
        require(!vaults[_vault].enabled, "BattleflyAtlasStaker: vault is already added");
        require(_vaultData.fee + _vaultData.claimRate == FEE_DENOMINATOR, "BattleflyAtlasStaker: invalid vault info");

        Vault storage vault = vaults[_vault];
        vault.fee = _vaultData.fee;
        vault.claimRate = _vaultData.claimRate;
        vault.enabled = true;
        emit AddedVault(_vault, vault.fee, vault.claimRate);
    }

    /**
     * @dev Remove vault address
     */
    function removeVault(address _vault) public onlyOwner {
        Vault storage vault = vaults[_vault];
        require(vault.enabled, "BattleflyAtlasStaker: vault does not exist");
        vault.enabled = false;
        emit RemovedVault(_vault);
    }

    /**
     * @dev Set allowed locks
     */
    function setAllowedLocks(IAtlasMine.Lock[] memory _locks) public onlyOwner {
        allowedLocks = _locks;
    }

    /**
     * @dev Set treasury wallet address
     */
    /* function setTreasury(address _treasury) public onlyOwner {
        require(_treasury != address(0), "BattleflyAtlasStaker: invalid address");
        TREASURY_VAULT = IBattleflyTreasuryFlywheelVault(_treasury);
        emit SetTreasury(_treasury);
    }*/

    /**
     * @dev Set daily bot address
     */
    function setBattleflyBot(address _battleflyBot) public onlyOwner {
        require(_battleflyBot != address(0), "BattleflyAtlasStaker: invalid address");
        BATTLEFLY_BOT = _battleflyBot;
        emit SetBattleflyBot(_battleflyBot);
    }

    function setPause(bool _paused) external override onlyOwner {
        pausedUntil = _paused ? block.timestamp + 48 hours : 0;
        emit SetPause(_paused);
    }

    /**
     * @dev Set harvester emissions contract
     */
    /* function setHarvesterEmission(address _harvesterEmission) public onlyOwner {
        require(_harvesterEmission != address(0), "BattleflyAtlasStaker: invalid address");
        HARVESTER_EMISSION = IBattleflyHarvesterEmissions(_harvesterEmission);
    }*/

    /**
     * @dev Set Flywheel emissions contract
     */
    function setFlywheelEmissions(address flywheelEmissions_) public onlyOwner {
        require(flywheelEmissions_ != address(0), "BattleflyAtlasStaker: invalid address");
        FLYWHEEL_EMISSIONS = IFlywheelEmissions(flywheelEmissions_);
    }

    /**
     * @dev Set transition epoch
     */
    function setTransitionEpoch(uint64 transitionEpoch_) public onlyOwner {
        require(transitionEpoch_ >= currentEpoch, "BattleflyAtlasStaker: invalid transition epoch");
        transitionEpoch = transitionEpoch_;
    }

    /**
     * @dev Set vault details
     */
    function setVault(address _vault, uint16 _fee, uint16 _claimRate, bool _enabled) public onlyOwner {
        require(_vault != address(0), "BattleflyAtlasStaker: invalid address");
        vaults[_vault].fee = _fee;
        vaults[_vault].claimRate = _claimRate;
        vaults[_vault].enabled = _enabled;
    }

    // ============================== VIEW ==============================

    /**
     * @dev Validate the lock period
     */
    function isValidLock(IAtlasMine.Lock _lock) public view returns (bool) {
        for (uint256 i = 0; i < allowedLocks.length; i++) {
            if (allowedLocks[i] == _lock) {
                return true;
            }
        }
        return false;
    }

    /**
     * @dev Get AtlasMine TREASURE ERC1155 NFT address
     */
    function getTREASURE() public view returns (IERC1155Upgradeable) {
        return IERC1155Upgradeable(ATLAS_MINE.treasure());
    }

    /**
     * @dev Get AtlasMine LEGION ERC721 NFT address
     */
    function getLEGION() public view returns (IERC721Upgradeable) {
        return IERC721Upgradeable(ATLAS_MINE.legion());
    }

    /**
     * @dev Get Unstaked MAGIC amount
     */
    function getUnstakedAmount() public view returns (uint256 amount) {
        IAtlasMine.Lock[] memory locks = LOCKS;
        for (uint256 i = 0; i < locks.length; i++) {
            amount += unstakedAmount[locks[i]];
        }
    }

    /**
     * @dev Get claimable MAGIC emission.
     * Emissions are:
     *      Emissions from normal lock period +
     *      Emissions from retention period -
     *      Already received emissions
     */
    function getClaimableEmission(uint256 _depositId) public view override returns (uint256 emission, uint256 fee) {
        VaultStake memory vaultStake = vaultStakes[_depositId];
        if (currentEpoch > 0) {
            uint64 retentionLock = vaultStake.retentionUnlock == 0 ? currentEpoch + 1 : vaultStake.retentionUnlock - 1;
            uint64 x = vaultStake.retentionUnlock == 0 || vaultStake.retentionUnlock != vaultStake.unlockAt ? 0 : 1;
            uint256 totalEmission = _getEmissionsForPeriod(
                vaultStake.amount,
                vaultStake.lockAt,
                vaultStake.unlockAt - x,
                vaultStake.lock
            ) + _getEmissionsForPeriod(vaultStake.amount, vaultStake.unlockAt, retentionLock, vaultStake.lock);
            emission = totalEmission >= vaultStake.paidEmission ? totalEmission - vaultStake.paidEmission : 0;
        }
        Vault memory vault = vaults[vaultStake.vault];
        fee = (emission * vault.fee) / FEE_DENOMINATOR;
        emission -= fee;
    }

    /**
     * @dev Get total claimable MAGIC emission.
     * This includes atlasmine and harvester emissions
     */
    function getTotalClaimableEmission(
        uint256 _depositId
    ) public view override returns (uint256 emission, uint256 fee) {
        (uint256 emissionAtlas, uint256 feeAtlas) = getClaimableEmission(_depositId);
        (uint256 emissionHarvester, uint256 feeHarvester) = HARVESTER_EMISSION.getClaimableEmission(_depositId);
        emission = emissionAtlas + emissionHarvester;
        fee = feeAtlas + feeHarvester;
    }

    /**
     * @dev Get staked amount
     */
    function getDepositedAmount(uint256[] memory _depositIds) public view returns (uint256 amount) {
        for (uint256 i = 0; i < _depositIds.length; i++) {
            amount += vaultStakes[_depositIds[i]].amount;
        }
    }

    /**
     * @dev Get allowed locks
     */
    function getAllowedLocks() public view override returns (IAtlasMine.Lock[] memory) {
        return allowedLocks;
    }

    /**
     * @dev Get vault staked data
     */
    function getVaultStake(uint256 _depositId) public view override returns (VaultStake memory) {
        return vaultStakes[_depositId];
    }

    /**
     * @dev Gets the lock period in epochs
     */
    function getLockPeriod(IAtlasMine.Lock _lock) external view override returns (uint64 epoch) {
        return BattleflyAtlasStakerUtils.getLockPeriod(_lock, ATLAS_MINE) / 1 days;
    }

    /**
     * @dev Check if a vaultStake can be withdrawn
     */
    function canWithdraw(uint256 _depositId) public view override returns (bool withdrawable) {
        VaultStake memory vaultStake = vaultStakes[_depositId];
        withdrawable = (vaultStake.retentionUnlock > 0) && (vaultStake.retentionUnlock <= currentEpoch);
    }

    /**
     * @dev Check if a vaultStake can request a withdrawal
     */
    function canRequestWithdrawal(uint256 _depositId) public view override returns (bool requestable) {
        VaultStake memory vaultStake = vaultStakes[_depositId];
        requestable = (vaultStake.retentionUnlock == 0) && (currentEpoch >= (vaultStake.unlockAt - 14));
    }

    /**
     * @dev Get the depositIds of a user
     */
    function depositIdsOfVault(address vault) public view override returns (uint256[] memory depositIds) {
        return depositIdByVault[vault].values();
    }

    /**
     * @dev Get the number of active AtlasMine positions
     */
    function activeAtlasPositionSize() public view override returns (uint256) {
        return activePositionIds.length();
    }

    /**
     * @dev Get the a vault object belonging to a vault address
     */
    function getVault(address _vault) public view override returns (Vault memory) {
        return vaults[_vault];
    }

    /**
     * @dev Get APY for epoch
     */
    function getApyAtEpochIn1000(uint64 epoch) public view override returns (uint256) {
        if (epoch == 0) {
            return 0;
        }
        uint256 totalPerShare = totalPerShareAtEpochForLock[IAtlasMine.Lock.twoWeeks][epoch] -
            totalPerShareAtEpochForLock[IAtlasMine.Lock.twoWeeks][epoch - 1];
        return ((totalPerShare * 365 * 100 * 1000) / 1e28) + HARVESTER_EMISSION.getApyAtEpochIn1000(epoch);
    }

    /**
     * @dev Get active atlasmine position IDs
     */
    function getActivePositionIds() public view override returns (uint256[] memory) {
        return activePositionIds.values();
    }

    // ============================== Internal ==============================

    /**
     * @dev recalculate and update the emissions per share per lock period and per epoch
     *      1 share is 1 wei of Magic.
     */
    function _updateEmissionsForEpoch(uint256 position, uint256 endPosition) private returns (uint256 totalEmission) {
        uint256[] memory positionIds = activePositionIds.values();

        // Total emissions of the current epoch are at least as much as the total emissions of the previous epoch
        if (position == 0) {
            for (uint256 i = 0; i < LOCKS.length; i++) {
                totalEmissionsAtEpochForLock[LOCKS[i]][currentEpoch] = currentEpoch > 0
                    ? totalEmissionsAtEpochForLock[LOCKS[i]][currentEpoch - 1]
                    : 0;
            }
        }

        // Calculate the total amount of pending emissions and the total deposited amount for each lock period in the current epoch
        for (uint256 j = position; j < endPosition; j++) {
            uint256 pendingRewards = ATLAS_MINE.pendingRewardsPosition(address(this), positionIds[j]);
            (, uint256 currentAmount, , , , , IAtlasMine.Lock _lock) = ATLAS_MINE.userInfo(
                address(this),
                positionIds[j]
            );
            totalEmission += pendingRewards;
            accruedEpochEmission += pendingRewards;
            totalEmissionsAtEpochForLock[_lock][currentEpoch] += pendingRewards;
            totalStakedAtEpochForLock[_lock][currentEpoch] += currentAmount;
        }
    }

    /**
     * @dev get the total amount of emissions of a certain period between two epochs.
     */
    function _getEmissionsForPeriod(
        uint256 amount,
        uint64 startEpoch,
        uint64 stopEpoch,
        IAtlasMine.Lock lock
    ) private view returns (uint256 emissions) {
        if (stopEpoch >= startEpoch && currentEpoch >= startEpoch) {
            uint256 totalEmissions = (amount * totalPerShareAtEpochForLock[lock][currentEpoch - 1]);
            uint256 emissionsTillExclusion = (amount * totalPerShareAtEpochForLock[lock][stopEpoch - 1]);
            uint256 emissionsTillInclusion = (amount * totalPerShareAtEpochForLock[lock][startEpoch - 1]);
            uint256 emissionsFromExclusion = emissionsTillExclusion > 0 ? (totalEmissions - emissionsTillExclusion) : 0;
            emissions = (totalEmissions - emissionsFromExclusion - emissionsTillInclusion) / ONE;
        }
    }

    /**
     * @dev Deposit MAGIC to AtlasMine
     */
    function _deposit(uint256 _depositId, uint256 _amount, IAtlasMine.Lock _lock) private returns (uint256) {
        // We only deposit to AtlasMine in the next epoch. We can unlock after the lock period has passed.
        uint64 lockAt = currentEpoch + 1;
        uint64 unlockAt = currentEpoch + 1 + (BattleflyAtlasStakerUtils.getLockPeriod(_lock, ATLAS_MINE) / 1 days);

        vaultStakes[_depositId] = VaultStake(lockAt, unlockAt, 0, _amount, 0, msg.sender, _lock);
        // Updated unstaked MAGIC amount
        unstakedAmount[_lock] += _amount;
        depositIdByVault[msg.sender].add(_depositId);
        emit NewDeposit(msg.sender, _amount, unlockAt, _depositId);
        return unlockAt;
    }

    /**
     * @dev Claim emissions for a depositId
     */
    function _claim(uint256 _depositId) internal returns (uint256) {
        VaultStake storage vaultStake = vaultStakes[_depositId];
        require(vaultStake.vault == msg.sender, "BattleflyAtlasStaker: caller is not a correct vault");
        uint256 harvesterClaim = HARVESTER_EMISSION.claim(_depositId);
        (uint256 emission, uint256 fee) = getClaimableEmission(_depositId);
        if (emission > 0) {
            MAGIC.safeTransfer(msg.sender, emission);
            if (fee > 0) {
                MAGIC.approve(address(TREASURY_VAULT), fee);
                TREASURY_VAULT.topupMagic(fee);
            }
            uint256 amount = emission + fee;
            vaultStake.paidEmission += amount;
            emit ClaimEmission(msg.sender, emission + harvesterClaim, _depositId);
        }
        emission += harvesterClaim;
        return emission;
    }

    // ============================== Modifiers ==============================

    modifier onlySuperAdmin() {
        require(superAdmins[msg.sender], "BattleflyAtlasStaker: caller is not a super admin");
        _;
    }

    modifier onlyWhitelistedVaults() {
        require(vaults[msg.sender].enabled, "BattleflyAtlasStaker: caller is not whitelisted");
        _;
    }

    modifier onlyAvailableLock(IAtlasMine.Lock _lock) {
        require(isValidLock(_lock), "BattleflyAtlasStaker: invalid lock period");
        _;
    }

    modifier onlyBattleflyBot() {
        require(msg.sender == BATTLEFLY_BOT, "BattleflyAtlasStaker: caller is not a battlefly bot");
        _;
    }

    modifier whenNotPaused() {
        require(block.timestamp > pausedUntil, "BattleflyAtlasStaker: contract paused");
        _;
    }
}

