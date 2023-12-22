// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";

interface ICoffee is IERC20 {
    error NotMinter();
    error NotOwner();
    
    function mint(address, uint256) external returns (bool);

    function minter() external returns (address);

}

