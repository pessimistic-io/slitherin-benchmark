// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.6.12;

interface IOreoBooster {
  function userStakingNFT(address _stakeToken, address _user) external view returns (address, uint256);
}

