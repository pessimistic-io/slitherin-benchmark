// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import {ILiquidityManager} from "./ILiquidityManager.sol";
import {SafeERC20, IERC20} from "./SafeERC20.sol";
import {AccessControl} from "./AccessControl.sol";

import {FullMath} from "./FullMath.sol";
import {TickMath} from "./TickMath.sol";
import {LiquidityAmounts} from "./LiquidityAmounts.sol";
import {IAlgebraPool} from "./IAlgebraPool.sol";

import {IAutoRebalancer} from "./IAutoRebalancer.sol";

/// @title Limit Rebalancer
/// @author @lance-alot
/// @notice Limit Rebalancer for an Algebra Liquidity Manager
contract LimitRebalancer is IAutoRebalancer, AccessControl {
    using SafeERC20 for IERC20;

    /*****************************************************************/
    /******************            EVENTS           ******************/
    /*****************************************************************/

    event AutoRebalance();

    /*****************************************************************/
    /******************          CONSTANTS         ******************/
    /*****************************************************************/

    int24 internal constant LIMIT_WIDTH = 1;
    bytes32 internal constant ADVISOR_ROLE = keccak256("ADVISOR_ROLE");
    ILiquidityManager internal immutable LIQUIDITY_MANAGER;

    /*****************************************************************/
    /******************         CONSTRUCTOR         ******************/
    /*****************************************************************/

    constructor(address _admin, address _advisor, address _liquidityManager) {
        require(_admin != address(0), "_admin should be non-zero");
        require(_advisor != address(0), "_advisor should be non-zero");
        require(_liquidityManager != address(0), "_liquidityManager should be non-zero");

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADVISOR_ROLE, _advisor);
        LIQUIDITY_MANAGER = ILiquidityManager(_liquidityManager);
    }
    /********************************************************************/
    /****************** EXTERNAL ADMIN-ONLY FUNCTIONS  ******************/
    /********************************************************************/

    /// @notice Transfer tokens to recipient from the contract
    /// @param token Address of token
    /// @param recipient Recipient Address
    function rescueERC20(IERC20 token, address recipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(recipient != address(0), "RNZ");
        token.safeTransfer(recipient, token.balanceOf(address(this)));
    }

    /// @notice auto rebalance the pool via liquidity manager
    /// @param  outMin min amount0,1 returned for shares of liq
    function autoRebalance(uint256[4] calldata outMin) external onlyRole(ADVISOR_ROLE) returns (
        int24 limitLower, int24 limitUpper, int24 baseLower, int24 baseUpper
    ){
        // avoid stack too deep
        {
            (bool surplus0, int24 currentTick) = _liquidityOptions();
            int24 tickSpacing = LIQUIDITY_MANAGER.tickSpacing();
            if (!surplus0) {
                // extra token1 in limit position = limit below
                limitUpper = (currentTick / tickSpacing) * tickSpacing - tickSpacing;

                if (limitUpper == currentTick) limitUpper = limitUpper - tickSpacing;

                limitLower = limitUpper - (tickSpacing * LIMIT_WIDTH);
            } else {
                // extra token0 in limit position = limit above
                limitLower = (currentTick / tickSpacing) * tickSpacing + tickSpacing;

                if (limitLower == currentTick) limitLower = limitLower + tickSpacing;

                limitUpper = limitLower + (tickSpacing * LIMIT_WIDTH);
            }
        }

        (baseLower, baseUpper,,) = LIQUIDITY_MANAGER.positionsSettings();

        int24[4] memory ranges;
        ranges[0] = baseLower;
        ranges[1] = baseUpper;
        ranges[2] = limitLower;
        ranges[3] = limitUpper;

        uint256[4] memory inMax;
        inMax[0] = type(uint256).max;
        inMax[1] = type(uint256).max;
        inMax[2] = type(uint256).max;
        inMax[3] = type(uint256).max;

        uint256[4] memory inMin;
        LIQUIDITY_MANAGER.rebalance(ranges, inMax, inMin, outMin);
        emit AutoRebalance();
    }

    /// @notice compound pending fees
    function compound(uint256[4] calldata inMax) external onlyRole(ADVISOR_ROLE) {
        uint256[4] memory inMin;
        LIQUIDITY_MANAGER.compound(inMax, inMin);

        emit Compound(inMax);
    }

    /********************************************************************/
    /******************       INTERNAL FUNCTIONS       ******************/
    /********************************************************************/

    /// @notice get liquidity options
    /// @return currentTick The current tick
    /// @return surplus0 Whether there is more token0 unutilized than token1
    function _liquidityOptions() internal view returns (bool, int24) {
        // get total amounts of token0,1 in pool and on the contract
        (uint256 total0, uint256 total1) = LIQUIDITY_MANAGER.getTotalAmounts();

        // get current price and tick
        (uint160 sqrtRatioX96, int24 currentTick,,,,,,) = LIQUIDITY_MANAGER.pool().globalState();

        (int24 baseLower, int24 baseUpper,,) = LIQUIDITY_MANAGER.positionsSettings();

        // get amount of liquidity for the base position at the current price
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96, TickMath.getSqrtRatioAtTick(baseLower), TickMath.getSqrtRatioAtTick(baseUpper), total0, total1
        );

        // get amount of token0,1 in base position
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96, TickMath.getSqrtRatioAtTick(baseLower), TickMath.getSqrtRatioAtTick(baseUpper), liquidity
        );

        // get current price
        uint256 price = FullMath.mulDiv(uint256(sqrtRatioX96), (uint256(sqrtRatioX96)), 2 ** (96 * 2));

        // do we have a surplus of token0?
        bool surplus0 = (total0 - amount0) * price > (total1 - amount1);
        return (surplus0, currentTick);
    }
}

