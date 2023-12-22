//SPDX-License-Identifier:MIT
pragma solidity ^0.8.16;

interface IStrandsStrategy {

  function setBoard(uint boardId) external returns (uint roundEnds);

  function doTrade(uint strikeId) external returns (int balChange,uint[] memory tradePositionIds);

  function deltaHedge(uint hedgeType) external returns (int balChange,uint[] memory hedgePositionIds);

  function reducePosition(uint closeAmount) external returns (int balChange,uint[] memory positionIds);

  function hasOpenPosition() external view returns (bool);

  function emergencyCloseAll() external returns(int balChange);

  function returnFundsToVault() external;
}

