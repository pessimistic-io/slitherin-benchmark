// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.13;

import "./ERC20_IERC20.sol";

interface IERC20Burnable is IERC20 {
    function burnFrom(address account, uint256 amount) external;
}

