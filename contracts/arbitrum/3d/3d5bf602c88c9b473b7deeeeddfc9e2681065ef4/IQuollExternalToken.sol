// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./IERC20Upgradeable.sol";

interface IQuollExternalToken is IERC20Upgradeable {
    function mint(address, uint256) external;

    function burn(address, uint256) external;
}

