// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IERC20MetadataUpgradeable.sol";

interface IWETH9 is IERC20MetadataUpgradeable {
    function deposit() external payable;

    function withdraw(uint256 wad) external;
}

