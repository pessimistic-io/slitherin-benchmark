// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./IWBNB.sol";
import "./Address.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

library TransferHelper {

    using Address for address payable;
    using SafeERC20 for IERC20;

    uint constant public ARBITRUM_ONE = 42161;
    address constant public ARBITRUM_ONE_WRAPPED = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    uint constant public ARBITRUM_GOERLI = 421613;
    address constant public ARBITRUM_GOERLI_WRAPPED = 0xe39Ab88f8A4777030A534146A9Ca3B52bd5D43A3;

    function transfer(address token, address to, uint256 amount) internal {
        if (token != nativeWrapped()) {
            IERC20(token).safeTransfer(to, amount);
        } else {
            IWBNB(token).withdraw(amount);
            payable(to).sendValue(amount);
        }
    }

    function transferFrom(address token, address from, uint256 amount) internal {
        if (token != nativeWrapped()) {
            IERC20(token).safeTransferFrom(from, address(this), amount);
        } else {
            require(msg.value >= amount, "insufficient transfers");
            IWBNB(token).deposit{value: amount}();
        }
    }

    function nativeWrapped() internal view returns (address) {
        uint256 chainId = block.chainid;
        if (chainId == ARBITRUM_ONE) {
            return ARBITRUM_ONE_WRAPPED;
        } else if (chainId == ARBITRUM_GOERLI) {
            return ARBITRUM_GOERLI_WRAPPED;
        } else {
            revert("unsupported chain id");
        }
    }
}

