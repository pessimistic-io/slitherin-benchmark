// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { IERC20Upgradeable } from "./IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "./SafeERC20Upgradeable.sol";

import { AbstractVault } from "./AbstractVault.sol";

/* 
Inherits from the AbstractVault contract.
Refer to the AbstractVault contract.
*/

contract ERC20Vault is AbstractVault {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    
    function _addLiquidity(uint256 _amountIn) internal override returns (uint256) {
        uint256 before = IERC20Upgradeable(underlyingToken).balanceOf(address(this));
        IERC20Upgradeable(underlyingToken).safeTransferFrom(msg.sender, address(this), _amountIn);
        _amountIn = IERC20Upgradeable(underlyingToken).balanceOf(address(this)) - before;

        return _amountIn;
    }
}

