// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./ERC20_IERC20.sol";

interface IERC20Mintbale is IERC20{
    function mint(uint amount, address account) external;
}

