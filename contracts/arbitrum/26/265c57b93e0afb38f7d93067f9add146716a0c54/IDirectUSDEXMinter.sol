// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;


interface IDirectUSDEXMinter {

    function mint(uint256 _amount) external returns (bool);

}

