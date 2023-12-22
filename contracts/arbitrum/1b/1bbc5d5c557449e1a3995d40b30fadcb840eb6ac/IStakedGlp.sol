// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "./ReentrancyGuard.sol";

interface IStakedGlp {
    function approve(address _spender, uint256 _amount) external returns (bool);
    function transfer(address _recipient, uint256 _amount) external returns (bool);
    function transferFrom(address _sender, address _recipient, uint256 _amount) external returns (bool);
}


