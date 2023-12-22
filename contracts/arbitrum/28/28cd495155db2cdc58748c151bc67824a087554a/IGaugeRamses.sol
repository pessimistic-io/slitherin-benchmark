// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

interface IGaugeRamses {

    function depositAll(uint tokenId) external;

    function deposit(uint amount, uint tokenId) external;

    function withdrawAll() external;

    function withdraw(uint amount) external;

    function withdrawToken(uint amount, uint tokenId) external;

    function notifyRewardAmount(address token, uint amount) external;

    function getReward(address account, address[] memory tokens) external;

    function claimFees() external returns (uint claimed0, uint claimed1);

    function underlying() external view returns (address);

    function derivedSupply() external view returns (uint);

    function derivedBalances(address account) external view returns (uint);

    function totalSupply() external view returns (uint);

    function balanceOf(address account) external view returns (uint);

    function rewardTokens(uint id) external view returns (address);

    function isRewardToken(address token) external view returns (bool);

    function rewardTokensLength() external view returns (uint);

    function derivedBalance(address account) external view returns (uint);

    function left(address token) external view returns (uint);

    function earned(address token, address account) external view returns (uint);

    function tokenIds(address account) external view returns (uint);

}

