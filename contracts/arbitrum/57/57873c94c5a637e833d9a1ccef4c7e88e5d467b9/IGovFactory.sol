// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

interface IGovFactory {
  event ProjectCreated(address indexed project, uint256 index);

  function owner() external view returns (address);

  function komV() external view returns (address);

  function beacon() external view returns (address);

  function savior() external view returns (address);

  function saleGateway() external view returns (address);

  function operational() external view returns (address);

  function marketing() external view returns (address);

  function treasury() external view returns (address);

  function operationalPercentage_d2() external view returns (uint256);

  function marketingPercentage_d2() external view returns (uint256);

  function treasuryPercentage_d2() external view returns (uint256);

  function allProjectsLength() external view returns (uint256);

  function allPaymentsLength() external view returns (uint256);

  function allChainsStakedLength() external view returns (uint256);

  function allProjects(uint256) external view returns (address);

  function allPayments(uint256) external view returns (address);

  function allChainsStaked(uint256) external view returns (uint256);

  function getPaymentIndex(address) external view returns (uint256);

  function getChainStakedIndex(uint256) external view returns (uint256);

  function isKnown(address) external view returns (bool);

  function setPayment(address _token) external;

  function removePayment(address _token) external;

  function setChainStaked(uint256[] calldata _chainID) external;

  function removeChainStaked(uint256[] calldata _chainID) external;

  function config(
    address _komV,
    address _beacon,
    address _saleGateway,
    address _savior,
    address _operational,
    address _marketing,
    address _treasury
  ) external;
}

