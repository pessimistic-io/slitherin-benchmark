pragma solidity ^0.8.0;

import { SafeTransferLib, ERC20 } from "./SafeTransferLib.sol";

import "./Kernel.sol";

// Module dependencies
import { XGMBL } from "./XGMBL.sol";
import { GMBL } from "./GMBL.sol";
import { ROLES } from "./ROLES.sol";
import { REWRD } from "./REWRD.sol";
import { REWRDV2 } from "./REWRDV2.sol";

import { IxGMBLTokenUsage } from "./IxGMBLTokenUsage.sol";

contract StakedPolicy is Policy {

    error StakedPolicy_InvalidStakeBoostMultiplier();
    error StakedPolicy_InvalidStakeBoostPeriod();
    error StakedPolicy_ConversionsPaused();

    event StakeBoostMultiplierSet(uint16 oldMultiplier, uint16 newMultiplier);
    event StakeBoostPeriodSet(uint256 startTime, uint256 endTime);

    XGMBL public xGMBL;
    GMBL public gmbl;
    ROLES public roles;
    REWRD public rewrdV1;
    REWRDV2 public rewrdV2;

    struct StakeBoost {
        uint256 start;
        uint256 end;
    }

    StakeBoost public stakeBoostPeriod;
    uint16 public StakeBoostMultiplier; // 10000 = 100%

    bool public paused;

    mapping(address => uint256) public imbalanceWhitelist;

    constructor(Kernel kernel_) Policy(kernel_) {
        // default staked amount == 100% of GMBL converted
        StakeBoostMultiplier = 10000;
    }

    modifier OnlyOwner {
        roles.requireRole("stakingmanager", msg.sender);
        _;
    }

    function configureDependencies() external override onlyKernel returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](5);
        dependencies[0] = toKeycode("XGMBL");
        dependencies[1] = toKeycode("GMBLE");
        dependencies[2] = toKeycode("ROLES");
        dependencies[3] = toKeycode("REWRD");
        dependencies[4] = toKeycode("RWRD2");

        xGMBL = XGMBL(getModuleAddress(dependencies[0]));
        gmbl = GMBL(getModuleAddress(dependencies[1]));
        roles = ROLES(getModuleAddress(dependencies[2]));
        rewrdV1 = REWRD(getModuleAddress(dependencies[3]));
        rewrdV2 = REWRDV2(getModuleAddress(dependencies[4]));
    }

    function requestPermissions() external pure override returns (Permissions[] memory requests) {
        Keycode XGMBL_KEYCODE = toKeycode("XGMBL");
        Keycode REWRD_KEYCODE = toKeycode("REWRD");
        Keycode REWRDV2_KEYCODE = toKeycode("RWRD2");

        requests = new Permissions[](14);
        requests[0] = Permissions(XGMBL_KEYCODE, XGMBL.convert.selector);
        requests[1] = Permissions(XGMBL_KEYCODE, XGMBL.allocate.selector);
        requests[2] = Permissions(XGMBL_KEYCODE, XGMBL.updateRedeemSettings.selector);
        requests[3] = Permissions(XGMBL_KEYCODE, XGMBL.updateRewardsAddress.selector);
        requests[5] = Permissions(XGMBL_KEYCODE, XGMBL.updateTransferWhitelist.selector);
        requests[6] = Permissions(XGMBL_KEYCODE, XGMBL.deallocate.selector);
        requests[7] = Permissions(XGMBL_KEYCODE, XGMBL.redeem.selector);
        requests[8] = Permissions(XGMBL_KEYCODE, XGMBL.finalizeRedeem.selector);
        requests[9] = Permissions(XGMBL_KEYCODE, XGMBL.updateRedeemRewardsAddress.selector);
        requests[10] = Permissions(XGMBL_KEYCODE, XGMBL.cancelRedeem.selector);
        requests[11] = Permissions(XGMBL_KEYCODE, XGMBL.burn.selector);
        requests[12] = Permissions(REWRD_KEYCODE, REWRD.harvestRewards.selector);
        requests[13] = Permissions(REWRDV2_KEYCODE, REWRDV2.harvestRewards.selector);
    }

    // ######################## ~ MODULE ENTRANCES ~ ########################

    /// @notice Converts `amount` of msg.sender's GMBL to xGMBL, accounting for stake boost
    /// @param amount Amount of GMBL to convert
    function convert(uint256 amount) external {
        if (paused) revert StakedPolicy_ConversionsPaused();

        uint256 boostedAmount = _getStakeBoost(amount);
        _convert(amount, boostedAmount);
    }

    /// @notice Allocates `amount` of msg.sender's xGMBL to the rewards usage
    /// @param amount Amount to allocate
    /// @param usageData Optional calldata to adhere to xGMBL usage interface
    function allocate(uint256 amount, bytes calldata usageData) external {
        _allocate(amount, usageData);
    }

    /// @notice Atomically performs convert() and allocate() for msg.sender
    /// @param amount Amount of GMBL to convert to xGMBL and allocate to rewards
    /// @param usageData Optional calldata to adhere to xGMBL usage interface
    function convertAndAllocate(uint256 amount, bytes calldata usageData) external {
        if (paused) revert StakedPolicy_ConversionsPaused();

        uint256 boostedAmount = _getStakeBoost(amount);
        _convert(amount, boostedAmount);
        _allocate(boostedAmount, usageData);
    }

    /// @notice Deallocates `amount` of msg.sender`s
    /// @dev Attempting to deallocate into any amount allocated in redeem entries will revert
    /// @param amount Amount of xGMBL to deallocate
    /// @param usageData Optional calldata to adhere to xGMBL usage interface
    function deallocate(uint256 amount, bytes calldata usageData) external {
        xGMBL.deallocate(msg.sender, amount, usageData);
    }

    /// @notice Starts redeem process for msg.sender's `amount` of xGMBL
    /// @param amount Amount of xGMBL to redeem
    /// @param duration Duration to linearly redeem % of underlying GMBL for xGMBL
    function redeem(uint256 amount, uint256 duration) external {
        xGMBL.redeem(msg.sender, amount, duration);
    }

    /// @notice Finalizes a redeem entry for msg.sender
    /// @param redeemIndex The redeem entry index of msg.sender to finalize
    function finalizeRedeem(uint256 redeemIndex) external {
        (,,,IxGMBLTokenUsage rewardsAddress,) = xGMBL.userRedeems(msg.sender, redeemIndex);
        if (address(rewardsAddress) != address(rewrdV2))
            xGMBL.updateRedeemRewardsAddress(msg.sender, redeemIndex);

        xGMBL.finalizeRedeem(msg.sender, redeemIndex);
    }

    /// @notice Helper function to migrate msg.sender's rewards allocation to a new address
    /// @param redeemIndex The redeem entry index of msg.sender to migrate
    function updateRedeemRewardsAddress(uint256 redeemIndex) external {
        xGMBL.updateRedeemRewardsAddress(msg.sender, redeemIndex);
    }

    /// @notice Cancels a redeem entry for msg.sender
    /// @param redeemIndex The redeem entry index to cancel
    function cancelRedeem(uint256 redeemIndex) external {
        xGMBL.cancelRedeem(msg.sender, redeemIndex);
    }

    /// @notice Burns `amount` of msg.sender's rewards allocaiton and cooresponding locked GMBL 1:1
    /// @dev must be unallocated xGMBL
    /// @param amount Amount to burn
    function burn(uint256 amount) external {
        xGMBL.burn(msg.sender, amount);
    }

    function _convert(uint256 amount, uint256 boostedAmount) private {
        xGMBL.convert(amount, boostedAmount, msg.sender);
    }

    function _allocate(uint256 amount, bytes calldata usageData) private {
        xGMBL.allocate(msg.sender, amount, usageData);
    }

    function _getStakeBoost(uint256 amount) private view returns (uint256 boost) {
        if (block.timestamp > stakeBoostPeriod.end || block.timestamp < stakeBoostPeriod.start) {
            return amount;
        }
        return amount * StakeBoostMultiplier / 10000;
    }

    function getAllocationImbalance(address account) public view returns (uint256 imbalance) {
        return xGMBL.rewardsAllocations(account) - rewrdV1.usersAllocation(account);
    }

    function getRedeemsAllocationImbalance(address account) public view returns (uint256 imblance, uint256 numRedeems) {
        uint256 redeemsAllocations;
        uint256 rewardsAllocations = rewrdV1.usersAllocation(account);
        numRedeems = xGMBL.getUserRedeemsLength(account);

        for(uint256 i = 0; i < numRedeems; ++i) {
            (,,,,uint256 RewardsAllocation) = xGMBL.userRedeems(account, i);
            redeemsAllocations += RewardsAllocation;
        }

        uint256 imbalance = redeemsAllocations > rewardsAllocations ? redeemsAllocations - rewardsAllocations : 0;
        return (imbalance, numRedeems);
    }

    /// @notice Migrates accounts affected by harvest allocaiton imabalnce bug
    /// by initializing redeems and allocating the difference before transferring the xGMBL to a newAccount
    /// @param newAccount new account to transfer all allocated/unallocated xGMBL to and allocate from
    function migrateImbalancedAccount(address newAccount) external {
        (uint256 redeemsImbalance, uint256 numRedeems) = getRedeemsAllocationImbalance(msg.sender);
        imbalanceWhitelist[msg.sender] -= redeemsImbalance;

        // Tops off rewards allocation so current redeems (if imbalanced) can be cancelled
        if (redeemsImbalance > 0) {
            gmbl.transfer(msg.sender, redeemsImbalance);
            xGMBL.convert(redeemsImbalance, redeemsImbalance, msg.sender);
            xGMBL.allocate(msg.sender, redeemsImbalance, hex"00");
        }

        // pops each redeem entry off to before migrating whole balance in one redeem
        for(uint256 i = 0; i < numRedeems; ++i) {
            xGMBL.cancelRedeem(msg.sender, 0);
        }

        _migrateImblancedAccount(newAccount);
    }

    /// @notice migrates whole balance of allocated/unallocated xgmbl to a newAccount and harvests remaining rewards
    function _migrateImblancedAccount(address newAccount) internal {
        uint256 imbalancedAmount = getAllocationImbalance(msg.sender);
        if (imbalancedAmount == 0) return;

        imbalanceWhitelist[msg.sender] -= imbalancedAmount;

        (uint256 allocatedAmount,) = xGMBL.xGMBLBalances(msg.sender);

        uint256 oldMinRatio = xGMBL.minRedeemRatio();
        uint256 oldMaxRatio = xGMBL.maxRedeemRatio();
        uint256 oldMinDuration = xGMBL.minRedeemDuration();
        uint256 oldMaxDuration = xGMBL.maxRedeemDuration();
        uint256 oldRedeemRewardsPercent = xGMBL.redeemRewardsAdjustment();

        xGMBL.updateRedeemSettings(oldMinRatio, oldMaxRatio, oldMinDuration, oldMaxDuration, 100);
        xGMBL.redeem(msg.sender, allocatedAmount, 180 days);
        xGMBL.updateRedeemSettings(oldMinRatio, oldMaxRatio, oldMinDuration, oldMaxDuration, oldRedeemRewardsPercent);

        gmbl.transfer(msg.sender, imbalancedAmount);

        xGMBL.convert(imbalancedAmount, imbalancedAmount, msg.sender);
        xGMBL.allocate(msg.sender, imbalancedAmount, hex"00");

        xGMBL.cancelRedeem(msg.sender, 0);

        // cancelled redeem is fully unallocated
        uint256 newXgmblBalance = xGMBL.balanceOf(msg.sender);

        xGMBL.updateTransferWhitelist(msg.sender, true);
        xGMBL.transferFrom(msg.sender, newAccount, newXgmblBalance);
        xGMBL.updateTransferWhitelist(msg.sender, false);

        rewrdV1.harvestRewards(msg.sender, address(gmbl));
    }

    // ######################## ~ MODULE MANAGERIAL ENTRANCES ~ ########################

    /**
     * @notice Role-guarded function to update redeem settings
     * @param minRedeemRatio Ratio of GMBL:xGMBL returned for a minimum duration redeem (default 50%)
     * @param maxRedeemRatio Ratio of GMBL:xGMBL returned for a maximum duration redeem (default 100%)
     * @param minRedeemDuration Minumum duration a redeem entry must be (default instant)
     * @param maxRedeemDuration Maximum duration a redeem entry can be to receive `maxRedeemRatio` of GMBL:xGMBL
     * @param redeemRewardsAdjustment Percent of redeeming xGMBL that can still be allocated to rewards during redemption
     */
    function updateRedeemSettings(
        uint256 minRedeemRatio,
        uint256 maxRedeemRatio,
        uint256 minRedeemDuration,
        uint256 maxRedeemDuration,
        uint256 redeemRewardsAdjustment
    ) external OnlyOwner {
        xGMBL.updateRedeemSettings(
            minRedeemRatio,
            maxRedeemRatio,
            minRedeemDuration,
            maxRedeemDuration,
            redeemRewardsAdjustment
        );
    }

    /// @notice Role-guarded function to update the rewards contract
    /// @dev accounts must migrate their existing redeem entries to finalize or cancel
    /// @param RewardsAddress_ new rewards usage contract
    function updateRewardsAddress(IxGMBLTokenUsage RewardsAddress_) external OnlyOwner {
        xGMBL.updateRewardsAddress(RewardsAddress_);
    }

    /// @notice Role-guarded function to update the transfer whitelist of xGMBL
    /// @param account Address that can send or receive xGMBL
    /// @param add Toggle for whitelist
    function updateTransferWhitelist(address account, bool add) external OnlyOwner {
        xGMBL.updateTransferWhitelist(account, add);
    }

    // ######################## ~ POLICY MANAGEMENT ~ ########################

    /// @notice Role-guarded function to sets stake boost multiplier of this policy
    /// @param newMultiplier percent (10000 == 100%) to boost conversions
    function setStakeBoostMultiplier(uint16 newMultiplier) external OnlyOwner {
        if (10000 > newMultiplier) revert StakedPolicy_InvalidStakeBoostMultiplier();

        emit StakeBoostMultiplierSet(StakeBoostMultiplier, newMultiplier);
        StakeBoostMultiplier = newMultiplier;
    }

    /// @notice Role-guarded function to set `start` and `end` of stake boost period
    /// @param start Start timestamp of stake boost period
    /// @param end End timestamp of stake boost period
    function startStakeBoostPeriod(uint256 start, uint256 end) external OnlyOwner {
        if (start > end || block.timestamp > end) revert StakedPolicy_InvalidStakeBoostPeriod();
        if (stakeBoostPeriod.end > start) revert StakedPolicy_InvalidStakeBoostPeriod();

        emit StakeBoostPeriodSet(start, end);
        stakeBoostPeriod.start = start;
        stakeBoostPeriod.end = end;
    }

    /// @notice Role-guarded function to cancel stake boost period
    function cancelStakeBoost() external OnlyOwner {
        emit StakeBoostPeriodSet(0, 0);
        stakeBoostPeriod.start = 0;
        stakeBoostPeriod.end = 0;
    }

    /// @notice Role-guarded function to pause conversion actions
    function pause(bool paused_) external OnlyOwner {
        paused = paused_;
    }

    function setWhitelistImbalancedAccount(address account, uint256 amount) external OnlyOwner {
        imbalanceWhitelist[account] = amount;
    }

    function setWhitelistImbalancedAccounts(address[] calldata accounts, uint256[] calldata amounts) external OnlyOwner {
        for(uint256 i = 0; i <  accounts.length; ++i) {
            imbalanceWhitelist[accounts[i]] = amounts[i];
        }
    }

    function withdrawERC20(ERC20 token, uint256 amount) external OnlyOwner {
        token.transfer(msg.sender, amount);
    }
}
