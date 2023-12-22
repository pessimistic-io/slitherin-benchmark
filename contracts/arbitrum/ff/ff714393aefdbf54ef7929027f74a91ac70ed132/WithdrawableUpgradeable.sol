// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ContextUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";

import "./Errors.sol";

abstract contract WithdrawableUpgradeable is OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address payable;

    // constants
    IERC20Upgradeable internal constant ZERO_ADDRESS = IERC20Upgradeable(address(0));

    // state variables
    address public treasury; // Address to transfer profit

    modifier withdrawable(address _to) {
        _require(_to == treasury || _to == owner(), Errors.NOT_WITHDRAWABLE);
        _;
    }

    // solhint-disable-next-line
    function __Withdrawable_init() internal initializer {
        __Ownable_init_unchained();
        __Withdrawable_init_unchained();
    }

    // solhint-disable-next-line
    function __Withdrawable_init_unchained() internal initializer {}

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    function withdraw(IERC20Upgradeable _token, address _to, uint _amount) external onlyOwner withdrawable(_to) {
        if (_token == ZERO_ADDRESS) payable(_to).sendValue(_amount);
        else _token.safeTransfer(_to, _amount);
    }

    function withdrawAll(IERC20Upgradeable _token, address _to) external onlyOwner withdrawable(_to) {
        if (_token == ZERO_ADDRESS) payable(_to).sendValue(address(this).balance);
        else _token.safeTransfer(_to, _token.balanceOf(address(this)));
    }
}

