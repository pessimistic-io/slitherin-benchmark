// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.17;

import {IERC20} from "./IERC20.sol";

interface ILPToken is IERC20 {
    function mint(address to, uint amount) external;

    function burnFrom(address account, uint256 amount) external;
}

