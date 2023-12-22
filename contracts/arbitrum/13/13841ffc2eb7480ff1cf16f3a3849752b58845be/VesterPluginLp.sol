// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC20} from "./IERC20.sol";
import {IStrategyHelper} from "./IStrategyHelper.sol";

contract VesterPluginLp {
    IStrategyHelper public strategyHelper;
    address public lpToken;
    uint256 public slippage;

    constructor(address _strategyHelper, address _lpToken, uint256 _slippage) {
        strategyHelper = IStrategyHelper(_strategyHelper);
        lpToken = _lpToken;
        slippage = _slippage;
    }

    function onClaim(address from, uint256, address token, uint256 amount) external {
        IERC20(token).approve(address(strategyHelper), amount);
        strategyHelper.swap(token, lpToken, amount, slippage, from);
    }

    function rescueToken(address token, uint256 amount) external {
        IERC20(token).transfer(msg.sender, amount);
    }
}

