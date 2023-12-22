// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IGame {
    function play(uint256 _rolls, uint256 _bet, uint256[50] memory _data, uint256 _stake) external;
    function getMaxPayout(uint256 _bet, uint256[50] memory _data) external view returns (uint256);
}
