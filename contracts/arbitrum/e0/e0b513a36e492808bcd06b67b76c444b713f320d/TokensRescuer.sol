//SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "./SafeERC20Upgradeable.sol";

import "./IERC20Upgradeable.sol";

import "./Initializable.sol";

import "./AddressUpgradeable.sol";

import "./ITokensRescuer.sol";

import "./CheckerZeroAddr.sol";

abstract contract TokensRescuer is
    Initializable,
    ITokensRescuer,
    CheckerZeroAddr
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    function __TokensRescuer_init_unchained() internal onlyInitializing {}

    function _rescueNativeToken(
        uint256 amount,
        address receiver
    ) internal onlyNonZeroAddress(receiver) {
        AddressUpgradeable.sendValue(payable(receiver), amount);
    }

    function _rescueERC20Token(
        address token,
        uint256 amount,
        address receiver
    ) internal virtual onlyNonZeroAddress(receiver) onlyNonZeroAddress(token) {
        IERC20Upgradeable(token).safeTransfer(receiver, amount);
    }

    uint256[50] private __gap;
}

