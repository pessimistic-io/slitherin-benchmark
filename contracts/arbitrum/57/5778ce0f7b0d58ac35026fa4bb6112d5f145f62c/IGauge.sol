// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface IGauge {
    function balanceOf(address user) external view returns (uint256);

    function deposit(uint256 amount, uint256 tokenId) external;

    function withdraw(uint256 amount) external;

    function withdrawToken(uint256 amount, uint256 tokenId) external;

    function getReward(address account, address[] memory tokens) external;

    function earned(
        address token,
        address account
    ) external view returns (uint256);

    function tokenIds(address account) external view returns (uint256);

    function rewardsListLength() external view returns (uint256);

    function rewards(uint256 index) external view returns (address);

    function rewardRate(address token) external view returns (uint);

    function derivedBalances(address account) external view returns (uint);
}

