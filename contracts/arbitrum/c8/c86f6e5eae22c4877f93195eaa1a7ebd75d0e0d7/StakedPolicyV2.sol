pragma solidity ^0.8.0;

import { SafeTransferLib, ERC20 } from "./SafeTransferLib.sol";

import "./Kernel.sol";

// Module dependencies
import { XGMBL } from "./XGMBL.sol";
import { XGMBLV2 } from "./XGMBLV2.sol";
import { GMBL } from "./GMBL.sol";
import { ROLES } from "./ROLES.sol";
import { REWRD } from "./REWRD.sol";
import { REWRDV2 } from "./REWRDV2.sol";

import { IxGMBLTokenUsage } from "./IxGMBLTokenUsage.sol";

contract StakedPolicyV2 is Policy {

    error StakedPolicy_InvalidStakeBoostMultiplier();
    error StakedPolicy_InvalidStakeBoostPeriod();
    error StakedPolicy_ConversionsPaused();

    event StakeBoostMultiplierSet(uint16 oldMultiplier, uint16 newMultiplier);
    event StakeBoostPeriodSet(uint256 startTime, uint256 endTime);

    XGMBL public xGMBL;
    XGMBLV2 public xGMBLV2;
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
        dependencies = new Keycode[](6);
        dependencies[0] = toKeycode("XGMBL");
        dependencies[1] = toKeycode("GMBLE");
        dependencies[2] = toKeycode("ROLES");
        dependencies[3] = toKeycode("REWRD");
        dependencies[4] = toKeycode("RWRDB");
        dependencies[5] = toKeycode("XGBLB");

        xGMBL = XGMBL(getModuleAddress(dependencies[0]));
        gmbl = GMBL(getModuleAddress(dependencies[1]));
        roles = ROLES(getModuleAddress(dependencies[2]));
        rewrdV1 = REWRD(getModuleAddress(dependencies[3]));
        rewrdV2 = REWRDV2(getModuleAddress(dependencies[4]));
        xGMBLV2 = XGMBLV2(getModuleAddress(dependencies[5]));
    }

    function requestPermissions() external pure override returns (Permissions[] memory requests) {
        Keycode XGMBL_KEYCODE = toKeycode("XGMBL");
        Keycode XGMBLV2_KEYCODE = toKeycode("XGBLB");
        Keycode REWRD_KEYCODE = toKeycode("REWRD");
        Keycode REWRDV2_KEYCODE = toKeycode("RWRDB");

        requests = new Permissions[](25);
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
        requests[12] = Permissions(XGMBLV2_KEYCODE, XGMBLV2.convert.selector);
        requests[13] = Permissions(XGMBLV2_KEYCODE, XGMBLV2.allocate.selector);
        requests[14] = Permissions(XGMBLV2_KEYCODE, XGMBLV2.updateRedeemSettings.selector);
        requests[15] = Permissions(XGMBLV2_KEYCODE, XGMBLV2.updateRewardsAddress.selector);
        requests[16] = Permissions(XGMBLV2_KEYCODE, XGMBLV2.updateTransferWhitelist.selector);
        requests[17] = Permissions(XGMBLV2_KEYCODE, XGMBLV2.deallocate.selector);
        requests[18] = Permissions(XGMBLV2_KEYCODE, XGMBLV2.redeem.selector);
        requests[19] = Permissions(XGMBLV2_KEYCODE, XGMBLV2.finalizeRedeem.selector);
        requests[20] = Permissions(XGMBLV2_KEYCODE, XGMBLV2.updateRedeemRewardsAddress.selector);
        requests[21] = Permissions(XGMBLV2_KEYCODE, XGMBLV2.cancelRedeem.selector);
        requests[22] = Permissions(XGMBLV2_KEYCODE, XGMBLV2.burn.selector);
        requests[23] = Permissions(REWRD_KEYCODE, REWRD.harvestRewards.selector);
        requests[24] = Permissions(REWRDV2_KEYCODE, REWRDV2.harvestRewards.selector);
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
        xGMBLV2.deallocate(msg.sender, amount, usageData);
    }

    /// @notice Starts redeem process for msg.sender's `amount` of xGMBL
    /// @param amount Amount of xGMBL to redeem
    /// @param duration Duration to linearly redeem % of underlying GMBL for xGMBL
    function redeem(uint256 amount, uint256 duration) external {
        xGMBLV2.redeem(msg.sender, amount, duration);
    }

    /// @notice Finalizes a redeem entry for msg.sender
    /// @param redeemIndex The redeem entry index of msg.sender to finalize
    function finalizeRedeem(uint256 redeemIndex) external {
        (,,,IxGMBLTokenUsage rewardsAddress,) = xGMBLV2.userRedeems(msg.sender, redeemIndex);
        if (address(rewardsAddress) != address(rewrdV2))
            xGMBLV2.updateRedeemRewardsAddress(msg.sender, redeemIndex);

        xGMBLV2.finalizeRedeem(msg.sender, redeemIndex);
    }

    /// @notice Helper function to migrate msg.sender's rewards allocation to a new address
    /// @param redeemIndex The redeem entry index of msg.sender to migrate
    function updateRedeemRewardsAddress(uint256 redeemIndex) external {
        xGMBLV2.updateRedeemRewardsAddress(msg.sender, redeemIndex);
    }

    /// @notice Cancels a redeem entry for msg.sender
    /// @param redeemIndex The redeem entry index to cancel
    function cancelRedeem(uint256 redeemIndex) external {
        xGMBLV2.cancelRedeem(msg.sender, redeemIndex);
    }

    /// @notice Burns `amount` of msg.sender's rewards allocaiton and cooresponding locked GMBL 1:1
    /// @dev must be unallocated xGMBL
    /// @param amount Amount to burn
    function burn(uint256 amount) external {
        xGMBLV2.burn(msg.sender, amount);
    }

    /// @notice Migrates allocated, unallocated, and redeeming xGMBL to xGMBLV2 without penalty
    function migrateToXGMBLV2() external {
        _cancelAllRedeems();
        _migrateXGMBLBalances();
        try rewrdV1.harvestRewards(msg.sender, address(gmbl)) { } // solhint-disable-line no-empty-blocks
        catch { } // solhint-disable-line no-empty-blocks
    }

    function _convert(uint256 amount, uint256 boostedAmount) private {
        xGMBLV2.convert(amount, boostedAmount, msg.sender);
    }

    function _allocate(uint256 amount, bytes calldata usageData) private {
        xGMBLV2.allocate(msg.sender, amount, usageData);
    }

    function _getStakeBoost(uint256 amount) private view returns (uint256 boost) {
        if (block.timestamp > stakeBoostPeriod.end || block.timestamp < stakeBoostPeriod.start) {
            return amount;
        }
        return amount * StakeBoostMultiplier / 10000;
    }

    function _cancelAllRedeems() internal {
        uint256 numRedeems = xGMBL.getUserRedeemsLength(msg.sender);

        for (uint256 i = 0; i < numRedeems; i++) {
            xGMBL.cancelRedeem(msg.sender, 0);
        }
    }

    function _migrateXGMBLBalances() internal {
        uint256 walletBalance = xGMBL.balanceOf(msg.sender);
        (uint256 allocatedAmount, ) = xGMBL.xGMBLBalances(msg.sender);

        uint256 gmblOut = walletBalance + allocatedAmount;

        uint256 startMinRedeemRatio = xGMBL.minRedeemRatio();
        uint256 startMaxRedeemRatio = xGMBL.maxRedeemRatio();
        uint256 startMinRedeemDuration = xGMBL.minRedeemDuration();
        uint256 startMaxRedeemDuration = xGMBL.maxRedeemDuration();
        uint256 startRedeemRewardsAdjustment = xGMBL.redeemRewardsAdjustment();

        // redeem all gmbl for no ratio penalty (min redeem ratio 100%)
        xGMBL.updateRedeemSettings(100, startMaxRedeemRatio, startMinRedeemDuration, startMaxRedeemDuration, startRedeemRewardsAdjustment);
        xGMBL.redeem(msg.sender, gmblOut, 0);
        xGMBL.updateRedeemSettings(startMinRedeemRatio, startMaxRedeemRatio, startMinRedeemDuration, startMaxRedeemDuration, startRedeemRewardsAdjustment);

        // convert and allocate to xGMBLv2
        _convert(gmblOut, gmblOut);
        xGMBLV2.allocate(msg.sender, gmblOut, hex'00');
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
        xGMBLV2.updateRedeemSettings(
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
        xGMBLV2.updateRewardsAddress(RewardsAddress_);
    }

    /// @notice Role-guarded function to update the transfer whitelist of xGMBL
    /// @param account Address that can send or receive xGMBL
    /// @param add Toggle for whitelist
    function updateTransferWhitelist(address account, bool add) external OnlyOwner {
        xGMBLV2.updateTransferWhitelist(account, add);
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
}
