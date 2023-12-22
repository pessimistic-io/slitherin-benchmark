// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IMatrix {
    function setUserRoundDetail(
        address _user,
        uint256 _round,
        uint256 _sub,
        uint256 _timestamp
    ) external returns (bool);

    function setAccountTimeVote(
        address _user,
        uint256 _round,
        uint256 _sub,
        uint256 _timestamp
    ) external returns (bool);
}

