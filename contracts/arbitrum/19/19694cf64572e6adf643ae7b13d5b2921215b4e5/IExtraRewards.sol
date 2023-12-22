// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IExtraRewards {
    function claim() external;
    function pending(address _user, address _token) external view returns (uint256);
}
