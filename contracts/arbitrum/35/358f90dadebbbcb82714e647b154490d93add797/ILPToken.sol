// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.0;

import {IERC20} from "./ERC20_IERC20.sol";

interface ILPToken is IERC20 {
    function mint(address to, uint256 amount) external;

    function burnFrom(address account, uint256 amount) external;
}

