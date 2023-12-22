// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20Upgradeable.sol";

interface IBugz is IERC20Upgradeable {

    function mint(address _to, uint256 _amount) external;

    function burn(address _from, uint256 _amount) external;
}
