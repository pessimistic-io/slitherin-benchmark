// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./Ownable.sol";
import "./IERC20.sol";
import "./Clones.sol";

import {StrategUserInteractionsTarget} from "./StrategUserInteractionsTarget.sol";
import { IStrategVault, StrategVaultSettings } from "./IStrategVault.sol";
import {IStrategVaultFactory} from "./IStrategVaultFactory.sol";
import {IStrategERC3525} from "./IStrategERC3525.sol";

error NotInitialized();
error NotOwner();

/**
 * @title StrategVaultFactory
 * @author Bliiitz
 * @dev Factory contract for deploying StrategVault instances.
 */
contract StrategVaultFactory is
    Ownable(msg.sender),
    StrategUserInteractionsTarget,
    IStrategVaultFactory //@note TO CHECK INIT OWNABLE
{
    bool initialized;

    uint256 public VAULT_VERSION;
    uint256 public ERC3525_VERSION;

    address public treasury;
    address public relayer;
    address public erc3525Implementation;
    address public vaultImplementation;

    uint256 public protocolFee;
    uint256 public vaultsLength;

    mapping(uint256 => address) public vaults;

    /**
     * @dev Set the underlying asset contract. This must be an ERC20-compatible contract (ERC20 or ERC777).
     */
    constructor() {}

    modifier onlyVaultOwner(address vault, address user) {
        if (IStrategVault(vault).owner() != user) revert NotOwner();
        _;
    }

    /**
     * @notice Deploy a new StrategVault contract.
     * @param _name The name of the vault.
     * @param _symbol The symbol of the vault.
     * @param _owner The address of the vault owner.
     * @param _asset The address of the underlying asset.
     * @param _strategy The strategy to be used by the vault.
     * @param _bufferSize The buffer size for the vault.
     * @param _creatorFees The creator fees for the vault.
     * @param _harvestFees The harvest fees for the vault.
     * @param _ipfsHash The IPFS hash associated with the vault.
     */
    function deployNewVault(
        string memory _name,
        string memory _symbol,
        address _owner,
        address _asset,
        uint256 _strategy,
        uint256 _bufferSize,
        uint256 _creatorFees,
        uint256 _harvestFees,
        string memory _ipfsHash
    ) external onlyStrategUserInteractions {
        if (VAULT_VERSION == 0 || ERC3525_VERSION == 0) revert NotInitialized();

        address vaultProxy = Clones.clone(vaultImplementation);
        address erc3525Proxy = Clones.clone(erc3525Implementation);
        uint256 vLength = vaultsLength;

        emit NewVault(
            vLength,
            vaultProxy,
            _name,
            _symbol,
            _asset,
            _owner,
            erc3525Proxy,
            vaultImplementation,
            _ipfsHash
        );

        IStrategVault(vaultProxy).initialize(
            _owner,
            erc3525Proxy,
            _name,
            _symbol,
            _asset,
            _strategy,
            _bufferSize,
            _creatorFees,
            _harvestFees
        );

        IStrategERC3525(erc3525Proxy).initialize(
            vaultProxy,
            _owner,
            _asset,
            owner(),
            _strategUserInteractions()
        );

        vaults[vaultsLength] = address(vaultProxy);
        vaultsLength += 1;
    }

    function setVaultStrat(
        address user,
        address vault,
        address[] memory _positionManagers,
        address[] memory _stratBlocks,
        bytes[] memory _stratBlocksParameters,
        address[] memory _harvestBlocks,
        bytes[] memory _harvestBlocksParameters
    ) external onlyStrategUserInteractions onlyVaultOwner(vault, user) {
        IStrategVault(vault).setStrat(
            _positionManagers,
            _stratBlocks,
            _stratBlocksParameters,
            _harvestBlocks,
            _harvestBlocksParameters
        );
    }

    function editVaultParams(
        address _user,
        address _vault,
        StrategVaultSettings[] memory settings,
        bytes[] memory data
    ) external onlyStrategUserInteractions onlyVaultOwner(_vault, _user) {
        IStrategVault vault = IStrategVault(_vault);
        uint256 changesLength = settings.length;
        for (uint i = 0; i < changesLength; i++) {
            if (settings[i] == StrategVaultSettings.TimelockParams) {
                (bool _enabled, uint256 _duration) = abi.decode(
                    data[i],
                    (bool, uint256)
                );
                vault.setTimelockParams(_enabled, _duration);
            }

            if (settings[i] == StrategVaultSettings.DepositLimits) {
                (
                    uint256 _minUserDeposit,
                    uint256 _maxUserDeposit,
                    uint256 _minVaultDeposit,
                    uint256 _maxVaultDeposit
                ) = abi.decode(data[i], (uint256, uint256, uint256, uint256));

                vault.setDepositLimits(
                    _minUserDeposit,
                    _maxUserDeposit,
                    _minVaultDeposit,
                    _maxVaultDeposit
                );
            }

            if (settings[i] == StrategVaultSettings.HoldingParams) {
                (address _token, uint256 _amount) = abi.decode(
                    data[i],
                    (address, uint256)
                );
                vault.setHoldingParams(_token, _amount);
            }

            if (settings[i] == StrategVaultSettings.EditWhitelist) {
                (
                    bool _add, 
                    address addr
                ) = abi.decode(data[i], (bool, address));

                vault.whitelist(_add, addr);
            }

            if (settings[i] == StrategVaultSettings.FeeParams) {
                (uint256 _creatorFees, uint256 _harvestFees) = abi.decode(
                    data[i],
                    (uint256, uint256)
                );
                vault.setFeeParams(_creatorFees, _harvestFees);
            }

            if (settings[i] == StrategVaultSettings.BufferParams) {
                (uint256 _bufferSize, uint256 _bufferDerivation) = abi.decode(
                    data[i],
                    (uint256, uint256)
                );
                vault.setBufferParams(_bufferSize, _bufferDerivation);
            }
        }
    }

    /**
     * @notice Upgrade the vault implementation contract.
     * @param _implementation The address of the new implementation contract.
     */
    function upgradeVault(address _implementation) external onlyOwner {
        VAULT_VERSION += 1;
        vaultImplementation = _implementation;
        emit NewVaultImplementation(VAULT_VERSION, _implementation);
    }

    /**
     * @notice Upgrade the ERC3525 implementation contract.
     * @param _implementation The address of the new implementation contract.
     */
    function upgradeERC3525(address _implementation) external onlyOwner {
        ERC3525_VERSION += 1;
        erc3525Implementation = _implementation;
        emit NewERC2535Implementation(ERC3525_VERSION, _implementation);
    }

    /**
     * @notice Update relayer contract contract.
     * @param _relayer The address of the new implementation contract.
     */
    function setRelayer(address _relayer) external onlyOwner {
        relayer = _relayer;
    }

    /**
     * @notice Perform emergency execution on a vault.
     * @param _vault The address of the vault to perform emergency execution on.
     * @param _targets The array of target addresses to execute emergency actions on.
     * @param _datas The array of data payloads for the emergency actions.
     */
    function vaultEmergencyExecution(
        address _vault,
        address[] memory _targets,
        bytes[] memory _datas
    ) external onlyOwner {
        IStrategVault(_vault).emergencyExecution(_targets, _datas);
    }

    /**
     * @notice Set the protocol fee.
     * @param _fee The new protocol fee.
     */
    function setProtocolFee(uint256 _fee) external onlyOwner {
        require(_fee < 2500);
        protocolFee = _fee;
    }

    /**
     * @notice Set the users interaction contract (Relayer usage).
     * @param _addr The new address
     */
    function setStrategUserInteractions(address _addr) external onlyOwner {
        _setStrategUserInteractions(_addr);
    }

    /**
     * @notice Get the users interaction contract (Relayer usage).
     */
    function strategUserInteractions() external view returns (address) {
        return _strategUserInteractions();
    }

    /**
     * @notice Get the batch vault addresses for a given array of indices.
     * @param _indexes The array of vault index.
     * @return An array of vault addresses corresponding to the given indices.
     */
    function getBatchVaultAddresses(
        uint256[] memory _indexes
    ) external view returns (address[] memory) {
        address[] memory vaultAddresses = new address[](_indexes.length);
        for (uint256 i = 0; i < _indexes.length; i++) {
            vaultAddresses[i] = vaults[_indexes[i]];
        }

        return vaultAddresses;
    }
}

