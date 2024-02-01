// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./ERC20.sol";

interface IWrappedNative is IERC20 {
    function deposit() external payable;
    function withdraw(uint wad) external;
}
