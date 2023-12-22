// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";

interface IToken is IERC20 {

    function mint(address investor, uint256 amount) external;
    function burnFrom(address account, uint256 amount) external;

    function holders() external view returns(uint256);
}

