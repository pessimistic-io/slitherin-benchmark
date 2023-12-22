// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IStrategyVault {
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function asset() external view returns (address);

    function emissionToken() external view returns (address);

    function owner() external view returns (address);

    function maxQueuePull() external view returns (uint256);

    function minDeposit() external view returns (uint256);

    function fundsDeployed() external view returns (bool);

    function deploymentId() external view returns (uint256);

    function weightId() external view returns (uint256);

    function weightProportion() external view returns (uint256);

    function fetchVaultWeights() external view returns (uint256[] memory);

    function totalAssets() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function hook() external view returns (address addr, uint16 command);

    function fetchVaultList()
        external
        view
        returns (address[] memory vaultList);
}

