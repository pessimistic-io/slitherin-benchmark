// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ContextUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";

abstract contract WithdrawableUpgradeable is OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address payable;

    function __Withdrawable_init() internal initializer {
        __Ownable_init_unchained();
        __Withdrawable_init_unchained();
    }
    function __Withdrawable_init_unchained() internal initializer {
    }

    function withdrawToken(IERC20Upgradeable _token) external onlyOwner {
        _token.safeTransfer(msg.sender, _token.balanceOf(address(this)));
    }
    function withdrawETH() external onlyOwner {
        payable(_msgSender()).sendValue(address(this).balance);
    }

}
