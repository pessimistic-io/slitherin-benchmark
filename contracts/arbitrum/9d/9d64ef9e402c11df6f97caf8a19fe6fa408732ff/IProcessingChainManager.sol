// SPDX-License-Identifier: BSD-3-Clause
// Copyright © 2023 TXA PTE. LTD.
pragma solidity 0.8.19;

interface IProcessingChainManager {
    function admin() external view returns (address);
    function participatingInterface() external view returns (address);
    function insuranceFund() external view returns (address);
    function fraudPeriod() external view returns (uint256);
    function rootProposalLockAmount() external view returns (uint256);
    function staking() external view returns (address);
    function rollup() external view returns (address);
    function relayer() external view returns (address);
    function fraudEngine() external view returns (address);
    function walletDelegation() external view returns (address);
    function oracle() external view returns (address);
    function supportedAsset(uint256 chainId, address asset) external view returns (uint8);
    function isValidator(address validator) external view returns (bool);
    function isSupportedAsset(uint256 chainId, address asset) external view returns (bool);
}

