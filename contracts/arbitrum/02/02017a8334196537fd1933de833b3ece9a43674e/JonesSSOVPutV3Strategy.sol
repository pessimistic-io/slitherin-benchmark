// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.10;

/**
 * Libraries
 */
import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {Curve2PoolAdapter} from "./Curve2PoolAdapter.sol";
import {SushiAdapter} from "./SushiAdapter.sol";

/**
 * Interfaces
 */
import {IStableSwap} from "./IStableSwap.sol";
import {IwETH} from "./IwETH.sol";
import {IUniswapV2Router02} from "./IUniswapV2Router02.sol";
import {JonesSSOVV3StrategyBase} from "./JonesSSOVV3StrategyBase.sol";
import {ISsovV3} from "./ISsovV3.sol";

contract JonesSSOVPutV3Strategy is JonesSSOVV3StrategyBase {
    using SafeERC20 for IERC20;
    using SushiAdapter for IUniswapV2Router02;
    using Curve2PoolAdapter for IStableSwap;

    /// Curve stable swap
    IStableSwap private constant stableSwap = IStableSwap(0x7f90122BF0700F9E7e1F688fe926940E8839F353);

    /// Selling route for swapping base token with USDC;
    address[] private route;

    /**
     * @dev Sets the values for {name}, {asset}, {SSOVP}, and {governor}
     */
    constructor(bytes32 _name, address _asset, address _SSOV, address _governor)
        JonesSSOVV3StrategyBase(_name, _asset, _SSOV, _governor)
    {
        if (_asset == wETH) {
            route = [USDC, wETH];
        } else {
            route = [USDC, wETH, _asset];
        }
        // Token spending approval for Curve 2pool
        IERC20(USDC).safeApprove(address(stableSwap), type(uint256).max);

        // Token spending approvals for SushiSwap
        IERC20(USDC).safeApprove(address(sushiRouter), type(uint256).max);
        IERC20(_asset).safeApprove(address(sushiRouter), type(uint256).max);

        // Token spending approval for SSOV-P
        IERC20(stableSwap).safeApprove(address(SSOV), type(uint256).max);
    }

    /**
     * @notice Sells the base asset for 2CRV
     * @param _baseAmount The amount of base asset to sell
     * @param _stableToken The address of the stable token that will be used as intermediary to get 2CRV
     * @param _minStableAmount The minimum amount of `_stableToken` to get when swapping base
     * @param _min2CrvAmount The minimum amount of 2CRV to receive
     * Returns the amount of 2CRV tokens
     */
    function sellBaseFor2Crv(
        uint256 _baseAmount,
        address _stableToken,
        uint256 _minStableAmount,
        uint256 _min2CrvAmount
    )
        public
        onlyRole(KEEPER)
        returns (uint256)
    {
        return stableSwap.swapTokenFor2Crv(
            asset, _baseAmount, _stableToken, _minStableAmount, _min2CrvAmount, address(this)
        );
    }

    /**
     * @notice Sells 2CRV for the base asset
     * @param _amount The amount of 2CRV to sell
     * @param _stableToken The address of the stable token to receive when removing 2CRV lp
     * @param _minStableAmount The minimum amount of `_stableToken` to get when swapping 2CRV
     * @param _minAssetAmount The minimum amount of base asset to receive
     * Returns the amount of base asset
     */
    function sell2CrvForBase(uint256 _amount, address _stableToken, uint256 _minStableAmount, uint256 _minAssetAmount)
        public
        onlyRole(KEEPER)
        returns (uint256)
    {
        return stableSwap.swap2CrvForToken(asset, _amount, _stableToken, _minStableAmount, _minAssetAmount, address(this));
    }

    /**
     * Sells USDC balance for the asset token
     * @param _minAssetOutputFromUSDCSwap Minimum asset output from swapping USDC.
     */
    function sellUSDCForAsset(uint256 _minAssetOutputFromUSDCSwap) public onlyRole(KEEPER) {
        sushiRouter.sellTokensForExactTokens(route, _minAssetOutputFromUSDCSwap, address(this), USDC);
    }

    /**
     * Sells 2CRV balance for USDC
     * @param _minUSDCOutput Minimum USDC output from selling 2crv.
     */
    function swap2CRVBalanceForUSDC(uint256 _minUSDCOutput) public onlyRole(KEEPER) {
        uint256 _2crvBalance = stableSwap.balanceOf(address(this));
        if (_2crvBalance > 0) {
            stableSwap.swap2CrvForStable(USDC, _2crvBalance, _minUSDCOutput);
        }
    }

    function updateSSOVAddress(ISsovV3 _newSSOV) public onlyRole(GOVERNOR) {
        // revoke old
        IERC20(stableSwap).safeApprove(address(SSOV), 0);

        // set new ssov
        SSOV = _newSSOV;

        // approve new
        IERC20(stableSwap).safeApprove(address(SSOV), type(uint256).max);
    }
}

