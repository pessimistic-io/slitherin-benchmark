// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

interface IBribe {
   function notifyRewardAmount(address token, uint amount) external;

   function left(address token) external view returns (uint);

   function _deposit(uint amount, uint tokenId) external;

   function _withdraw(uint amount, uint tokenId) external;

   function getRewardForOwner(uint tokenId, address[] memory tokens) external;

   function balanceOf(uint tokenId) external view returns (uint);

   function earned(address token, uint tokenId) external view returns (uint);

   function batchRewardPerToken(address token, uint maxRuns) external;

   function swapOutReward(uint i, address oldToken, address newToken) external;

   function totalSupply() external view returns (uint);

   function rewardsListLength() external view returns (uint);

   function rewards(uint256 r) external view returns (address);
}

