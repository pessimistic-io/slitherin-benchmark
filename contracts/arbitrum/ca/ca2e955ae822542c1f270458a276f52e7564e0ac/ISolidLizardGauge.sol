// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface ISolidLizardGauge {
    function balanceOf(address account) external view returns (uint);
    function claimFees() external returns (uint claimed0, uint claimed1);
    function deposit(uint amount, uint tokenId) external;
    function depositAll(uint amount) external;
    function earned(address reward, address account) external view returns (uint);
    function getReward(address account, address[] memory token) external;
    function withdraw(uint amount) external;
    function withdrawAll() external;
    function totalSupply() external view returns (uint);
}
