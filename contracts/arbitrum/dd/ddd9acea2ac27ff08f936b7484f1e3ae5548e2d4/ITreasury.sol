// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

interface ITreasury {
    function distribute(address _token, address _to, uint256 _amount) external;
}

