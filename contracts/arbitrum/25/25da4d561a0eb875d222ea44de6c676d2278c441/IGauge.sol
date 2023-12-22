// SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

interface IGauge {
    function depositAll(uint tokenId) external;
    function deposit(uint amount, uint tokenId) external;
    function withdrawAll() external;
    function withdraw(uint amount) external;
    function getReward(address account, address[] memory tokens) external;
    function balanceOf(address account) external view returns (uint);
}
