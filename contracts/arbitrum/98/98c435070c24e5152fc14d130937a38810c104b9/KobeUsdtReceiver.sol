// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./IERC20.sol";
import "./SafeERC20.sol";

// This contract is made to receive USDT from token swaps and then send them
// to the token. This is becaause of the following check in UniswapV2Pair's swap logic:
// require(to != _token0 && to != _token1, 'UniswapV2: INVALID_TO');
// so tokens cannot be sent directly to the Kobe token address

contract KobeUsdtReceiver {
    using SafeERC20 for IERC20;

    function giveMeToken(address _token) external returns (uint256 _bal) {
        _bal = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, _bal);
    }
}
