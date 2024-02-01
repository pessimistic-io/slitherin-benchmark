// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IPleoSynthVotesToken {
    function balanceOf(address owner) external view returns (uint256 balance);
}
