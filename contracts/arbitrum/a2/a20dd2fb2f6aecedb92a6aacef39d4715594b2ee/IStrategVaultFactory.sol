// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import { StrategVaultSettings } from "./IStrategVault.sol";

interface IStrategVaultFactory {
    struct PermitParams {
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    event NewVault(
        uint256 indexed id,
        address indexed addr,
        string name,
        string symbol,
        address asset,
        address indexed owner,
        address erc3525,
        address implementation,
        string ipfsHash
    );

    event NewVaultImplementation(uint256 indexed version, address implementation);

    event NewERC2535Implementation(uint256 indexed version, address implementation);

    function vaultsLength() external view returns (uint256);
    function vaults(uint256) external view returns (address);
    function relayer() external view returns (address);
    function protocolFee() external view returns (uint256);

    function deployNewVault(
        string memory _name,
        string memory _symbol,
        address _owner,
        address _asset,
        uint256 _strategy,
        uint256 _bufferSize,
        uint256 _creatorFees,
        uint256 _harvestFees,
        string memory ipfsHash
    ) external;

    function setVaultStrat(
        address user,
        address vault,
        address[] memory _positionManagers,
        address[] memory _stratBlocks,
        bytes[] memory _stratBlocksParameters,
        address[] memory _harvestBlocks,
        bytes[] memory _harvestBlocksParameters
    ) external;

    function editVaultParams(
        address user,
        address vault,
        StrategVaultSettings[] memory settings,
        bytes[] calldata data
    ) external;

    function getBatchVaultAddresses(uint256[] memory indexes) external view returns (address[] memory);
    function vaultEmergencyExecution(address _vault, address[] memory _targets, bytes[] memory _datas) external;
}

