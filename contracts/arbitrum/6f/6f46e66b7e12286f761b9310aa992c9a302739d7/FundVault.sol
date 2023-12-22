// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "./PermissionsEnumerable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./SafeMath.sol";

contract FundVault is PermissionsEnumerable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // =============================================================
    //                    Constructor
    // =============================================================
    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Must send to Event Pods for now
    function sendFunds(address currency, address eventPod, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20 token = IERC20(currency);
        token.safeTransfer(eventPod, amount);
    }
}
