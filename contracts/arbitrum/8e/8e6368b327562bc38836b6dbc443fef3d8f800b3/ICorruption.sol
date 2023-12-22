// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20Upgradeable.sol";

interface ICorruption is IERC20Upgradeable {
    function burn(address _account, uint256 _amount) external;
    function setCorruptionStreamBoost(address _account, uint32 _boost) external;
}

