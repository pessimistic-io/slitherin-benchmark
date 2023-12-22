// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;


interface IVault {
    function gov() external view returns (address);
    function swap(address _tokenIn, address _tokenOut, address _receiver) external returns (uint256);

}

