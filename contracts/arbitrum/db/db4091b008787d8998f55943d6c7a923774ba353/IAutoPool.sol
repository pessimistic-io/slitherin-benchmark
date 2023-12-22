// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.9.0;

interface IAutoPool {
    function deposit(uint256 _amountX, uint256 _amountY)
        external 
        returns (uint256 shares, uint256 effectiveX, uint256 effectiveY);
    function getTokenX() external view returns (address);
}

