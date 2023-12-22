// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

interface iLCPoolUniv3Ledger {
  // token0 -> token1 -> fee -> nftId
  function poolToNftId(address token0, address token1, uint24 fee) external view returns(uint256);
  function setPoolToNftId(address token0, address token1, uint24 fee, uint256 id) external;

  function getLastRewardAmount(uint256 tokenId) external view returns(uint256);
  function getUserLiquidity(address account, uint256 tokenId, uint256 basketId) external view returns(uint256);

  function updateInfo(
    address acc,
    uint256 tId,
    uint256 bId,
    uint256 liquidity,
    uint256 reward0,
    uint256 reward1,
    bool increase
  ) external returns(uint256, uint256);

  function getSingleReward(address acc, uint256 tId, uint256 bId, uint256 currentReward, bool cutfee)
    external view returns(uint256, uint256);
  function getReward(address account, uint256[] memory tokenId, uint256[] memory basketIds) external view
    returns(uint256[] memory, uint256[] memory);
  function poolInfoLength(uint256 tokenId) external view returns(uint256);
  function reInvestInfoLength(uint256 tokenId) external view returns(uint256);
}

