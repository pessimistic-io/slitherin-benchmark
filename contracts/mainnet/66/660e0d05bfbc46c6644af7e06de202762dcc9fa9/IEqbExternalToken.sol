// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./IERC20Upgradeable.sol";

interface IEqbExternalToken is IERC20Upgradeable {
    function mint(address, uint256) external;
}

