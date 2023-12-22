// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.10;

/**
 * Libraries
 */
import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {SushiRouterWrapper} from "./SushiRouterWrapper.sol";

/**
 * Interfaces
 */
import {IUniswapV2Router02} from "./IUniswapV2Router02.sol";
import {JonesSSOVV3StrategyBase} from "./JonesSSOVV3StrategyBase.sol";
import {ISsovV3} from "./ISsovV3.sol";

contract JonesSSOVCallV3Strategy is JonesSSOVV3StrategyBase {
    using SafeERC20 for IERC20;
    using SushiRouterWrapper for IUniswapV2Router02;

    /**
     * @dev Initialize the Strategy.
     * @param _name of Stategy.
     * @param _asset Base Asset of Strategy.
     * @param _SSOV Dopex SSOV contract the Strategy will interact with.
     * @param _governor of Strategy.
     */
    constructor(
        bytes32 _name,
        address _asset,
        address _SSOV,
        address _governor
    ) JonesSSOVV3StrategyBase(_name, _asset, _SSOV, _governor) {
        // Token spending approval for SSOV
        IERC20(asset).safeApprove(address(SSOV), type(uint256).max);
    }

    /**
     * @notice Used to convert any reward tokens received by the Strategy back to Base Asset.
     */
    function sellRewardTokensForBaseToken(
        address[] memory _rewardTokens,
        uint256[] memory _minBaseOutputAmounts
    ) public onlyRole(KEEPER) {
        address[][] memory routes = new address[][](_rewardTokens.length);
        for (uint256 i = 0; i < _rewardTokens.length; i++) {
            IERC20 rewardToken = IERC20(_rewardTokens[i]);

            if (asset == wETH) {
                routes[i] = new address[](2);
                routes[i][0] = address(rewardToken);
                routes[i][1] = wETH;
            } else {
                routes[i] = new address[](3);
                routes[i][0] = address(rewardToken);
                routes[i][1] = wETH;
                routes[i][2] = asset;
            }

            IERC20(rewardToken).safeApprove(
                address(sushiRouter),
                IERC20(rewardToken).balanceOf(address(this))
            );
        }

        sushiRouter.sellTokens(
            _minBaseOutputAmounts,
            _rewardTokens,
            address(this),
            routes
        );
    }

    function updateSSOVAddress(ISsovV3 _newSSOV) public onlyRole(GOVERNOR) {
        // revoke old
        IERC20(asset).safeApprove(address(SSOV), 0);

        // set new ssov
        SSOV = _newSSOV;

        // approve new
        IERC20(asset).safeApprove(address(SSOV), type(uint256).max);
    }
}

