// SPDX-License-Identifier: GPL2
pragma solidity 0.8.10;

import "./IERC20Upgradeable.sol";

interface IMintable is IERC20Upgradeable {
    function mint(address recipient, uint256 amount) external;
}

