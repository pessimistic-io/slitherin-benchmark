// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;


import { IERC20 } from "./IERC20.sol";


interface IERC20Tax is IERC20 {
    function transferWithoutFee(address to, uint256 amount) external returns (bool);
    function transferFromWithoutFee(address sender, address recipient, uint256 amount) external returns (bool);
}

