// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IERC20Upgradeable.sol";

interface IERC20UpgradeableExt is IERC20Upgradeable {
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

