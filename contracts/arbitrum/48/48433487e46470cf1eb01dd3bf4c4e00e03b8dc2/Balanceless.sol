//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "./AddressUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./TransferLib.sol";

abstract contract Balanceless {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address payable;
    using TransferLib for IERC20Upgradeable;

    event BalanceCollected(address indexed token, address indexed to, uint256 amount);

    /// @dev Contango contracts are never meant to hold a balance (apart from dust for gas optimisations).
    /// Given we interact with third parties, we may get airdrops, rewards or be sent money by mistake, this function can be use to recoup them
    function _collectBalance(
        address token,
        address payable to,
        uint256 amount
    ) internal {
        if (token == address(0)) {
            to.sendValue(amount);
        } else {
            IERC20Upgradeable(token).transferOut(address(this), to, amount);
        }
        emit BalanceCollected(token, to, amount);
    }
}

