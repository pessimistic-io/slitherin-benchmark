// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


interface IStrategVaultFactory {

    struct PermitParams {
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    event NewVault(address indexed addr, string name, string symbol, address asset, address indexed owner);

    function registry() external view returns (address);
    function feeCollector() external view returns (address);
    function vaultsLength() external view returns (uint256);
    function vaults(uint256) external view returns (address);

    function deployNewVault(
        string memory _name, 
        string memory _symbol,
        address _asset,
        uint256 _performanceFees
    ) external;

    function getOwnedVaultBy(address owner) external view returns(uint256[] memory);
    function getBatchVaultAddresses(uint256[] memory indexes) external view returns (address[] memory);
}
