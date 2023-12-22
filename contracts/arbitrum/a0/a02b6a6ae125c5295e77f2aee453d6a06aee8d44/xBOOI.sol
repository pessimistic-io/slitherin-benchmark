// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./IERC20.sol";

interface xBOOI is IERC20 {
    function enter(uint256 _amount) external;
    function leave(uint256 _amount) external;
    function xBOOForBOO(uint256 _xBOOAmount) external view returns (uint256);
    function BOOForxBOO(uint256 _booAmount) external view returns (uint256);
}
