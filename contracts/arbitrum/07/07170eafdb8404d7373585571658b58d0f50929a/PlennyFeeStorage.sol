// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./PlennyDappFactory.sol";
import "./IUniswapV2Router02.sol";

/// @title PlennyFeeStorage
/// @notice
/// @dev
contract PlennyFeeStorage {

    //  @notice Slipage percent
    uint256 public constant SLIPPAGE_PERCENT = 1000;
    /// @notice uniswap swapping margin
    uint256 public constant ETH_OUT_AMOUNT_MARGIN = 1000;
    /// @notice uniswap adding liquidity margin
    uint256 public constant ADD_LIQUIDITY_MARGIN = 1000;

    /// @notice buy back percentage
    uint256 public buyBackPercentagePl2;
    /// @notice user reward percentage
    uint256 public replenishRewardPercentage;
    /// @notice daily inflation percentage
    uint256 public dailyInflationRewardPercentage;
    /// @notice burning percentage
    uint256 public lpBurningPercentage;
    /// @notice threshold for burning
    uint256 public lpThresholdForBurning;
    /// @notice threshold for buyback
    uint256 public plennyThresholdForBuyback;
    /// @notice inflation amount per block
    uint256 public inflationAmountPerBlock;
    /// @notice last maintenance block
    uint256 public lastMaintenanceBlock;
    /// @notice maintenance block limit
    uint256 public maintenanceBlockLimit;
    /// @dev job id count
    uint256 internal jobIdCount;
    /// @notice array jobs
    mapping(uint256 => uint256) public jobs;
}

