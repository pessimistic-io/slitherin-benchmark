// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IPriceFeed{
    function getPrice(address _token) external view returns(uint256);
}
