// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

interface INode {
    function nodeReward(address _userAddr,uint256 ap,uint256 level,uint256 ca) external;
}

