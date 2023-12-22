//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20Upgradeable} from "./IERC20Upgradeable.sol";

interface IBones is IERC20Upgradeable {
    function mint(address _to, uint256 _amount) external;

    function burn(address _from, uint256 _amount) external;
}

