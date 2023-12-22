// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Ownable} from "./Ownable.sol";

import {IAccessControlLogic} from "./IAccessControlLogic.sol";
import {IVaultProxyAdmin} from "./IVaultProxyAdmin.sol";

import {IVaultFactory} from "./IVaultFactory.sol";

/// @title VaultFactory
/// @notice This contract is a vault factory that implements methods for creating new vaults
/// and updating them via the UpgradeLogic contract.
contract VaultFactory is IVaultFactory, Ownable {
    // =========================
    // Storage
    // =========================

    /// @inheritdoc IVaultFactory
    address public immutable upgradeLogic;

    /// @inheritdoc IVaultFactory
    address public immutable vaultProxyAdmin;

    /// @dev Array of `Vault` implementations to which
    /// the vault-proxy can delegate to.
    address[] private _implementations;

    /// @dev Indicates that the contract has been initialized.
    bool private _initialized;

    /// @dev Bridge receiver address
    address private dittoBridgeReceiver;

    // =========================
    // Initializer
    // =========================

    /// @dev Blocks any actions with the original implementation by setting
    /// the `_initialized` flag.
    /// @param _upgradeLogic The address of the `UpgradeLogic` contract.
    constructor(address _upgradeLogic, address _vaultProxyAdmin) {
        // set the address of the UpgradeLogic contract during deployment
        upgradeLogic = _upgradeLogic;
        vaultProxyAdmin = _vaultProxyAdmin;
    }

    /// @notice Initializing VaultFactory as a transparent upgradeable proxy.
    /// @dev Sets the owner of the factory as msg.sender.
    /// @dev If vaultFactory is already initialized - throws `VaultFactory_AlreadyInitialized` error.
    function initialize(address newOwner) external {
        // if vaultFactory is already initialized -> revert
        if (_initialized) {
            revert VaultFactory_AlreadyInitialized();
        }
        _initialized = true;

        // set the owner of the factory contract.
        _transferOwnership(newOwner);
    }

    // =========================
    // Admin methods
    // =========================

    /// @inheritdoc IVaultFactory
    function setBridgeReceiverContract(
        address _dittoBridgeReceiver
    ) external onlyOwner {
        dittoBridgeReceiver = _dittoBridgeReceiver;
    }

    // =========================
    // Vault implementation logic
    // =========================

    /// @inheritdoc IVaultFactory
    function addNewImplementation(address newImplemetation) external onlyOwner {
        _implementations.push(newImplemetation);
    }

    /// @inheritdoc IVaultFactory
    function implementation(
        uint256 version
    ) external view returns (address impl_) {
        _validateVersion(version);

        impl_ = _implementations[version - 1];
    }

    /// @inheritdoc IVaultFactory
    function versions() external view returns (uint256 versions_) {
        versions_ = _implementations.length;
    }

    // =========================
    // Main functions
    // =========================

    /// @inheritdoc IVaultFactory
    function predictDeterministicVaultAddress(
        address creator,
        uint16 vaultId
    ) external view returns (address predicted) {
        bytes memory initcode = _getVaultInitcode();
        bytes32 initcodeHash;
        bytes32 salt;

        assembly ("memory-safe") {
            // compute the hash of the initcode
            initcodeHash := keccak256(add(initcode, 32), mload(initcode))

            // compute the salt
            mstore(0, creator)
            mstore(32, vaultId)
            salt := keccak256(0, 64)

            // rewrite memory -> future allocation will be from beginning of the memory
            mstore(64, 128)
        }

        // compute the address of the vault proxy
        bytes32 _predicted = keccak256(
            abi.encodePacked(bytes1(0xff), address(this), salt, initcodeHash)
        );

        assembly ("memory-safe") {
            // casting bytes32 value to address size (20 bytes)
            predicted := _predicted
        }
    }

    /// @inheritdoc IVaultFactory
    function deploy(
        uint256 version,
        uint16 vaultId
    ) external returns (address) {
        return _deploy(msg.sender, version, vaultId);
    }

    /// @inheritdoc IVaultFactory
    function crossChainDeploy(
        address creator,
        uint256 version,
        uint16 vaultId
    ) external returns (address) {
        if (msg.sender != dittoBridgeReceiver) {
            revert VaultFactory_NotAuthorized();
        }

        return _deploy(creator, version, vaultId);
    }

    // =========================
    // Private functions
    // =========================

    function _deploy(
        address creator,
        uint256 version,
        uint16 vaultId
    ) private returns (address) {
        if (vaultId == 0) {
            revert VaultFactory_InvalidDeployArguments();
        }

        uint256 latestVersion = _validateVersion(version);

        // if `version` == 0, the latest version of vault is deployed
        if (version == 0) {
            version = latestVersion;
        }

        // The following section of code is used to create a new contract instance using create2 opcode.
        bytes memory vaultInitcode = _getVaultInitcode();

        address vault;

        assembly ("memory-safe") {
            // salt = keccak256(creator, vaultId)
            mstore(0, creator)
            mstore(32, vaultId)

            vault := create2(
                0,
                add(vaultInitcode, 32),
                mload(vaultInitcode),
                keccak256(0, 64)
            )
        }

        // create2 success check:
        // if the newly created `vault` has codesize == 0 ->
        // salt has already been used -> revert
        if (vault.code.length == 0) {
            revert VaultFactory_IdAlreadyUsed(creator, vaultId);
        }

        // stores the address of the `implementation` contract in the `vault` proxy
        IVaultProxyAdmin(vaultProxyAdmin).initializeImplementation(
            vault,
            _implementations[version - 1]
        );

        // sets the `creator` as the first `vault` owner and stores immutable `vaultId`
        IAccessControlLogic(vault).initializeCreatorAndId(creator, vaultId);

        emit VaultCreated(creator, vault, vaultId);

        return vault;
    }

    /// @dev Helper function to validate the `version`.
    function _validateVersion(
        uint256 version
    ) private view returns (uint256 latestVersion) {
        latestVersion = _implementations.length;

        // if the `version` number is greater than the length of the `_implementations` array
        // or the array is empty -> revert
        if (version > latestVersion || latestVersion == 0) {
            revert VaultFactory_VersionDoesNotExist();
        }
    }

    /// @dev Helper function to get the initcode of the vault proxy.
    function _getVaultInitcode() private view returns (bytes memory bytecode) {
        // playground:
        // https://www.evm.codes/playground?fork=shanghai&unit=Wei&callData=0x12345678&codeType=Mnemonic&code='zconstructor_zy00Fy50Fqzy0bFh4FCODEgzX1Fp~Fruntime_y00~.qkKgqq.kERjw~EQ~y2alI~qNOT~SLOAD~y40lfj11223344556677889900f~GAS~DELEGATEk*vh3~qpKgX1*vX2~y4elI~REVERTf*'~%5Cnz%2F%2F%20y-1B00998877665544332211vKSIZE~qh1*RETURNl~JUMPkCALLj~-20BhDUPgCOPY~flDEST_%20code~XSWAPKDATAF~zB%200xw.kvh2~-PUSH*~p%01*-.BFKX_fghjklpqvwyz~_
        //------------------------------------------------------------------------------//
        // Opcode  | Opcode + Arguments | Description    | Stack View                   //
        //------------------------------------------------------------------------------//
        // constructor code:                                                            //
        // 0x60    | 0x60 0x00          | PUSH1 0        | 0                            //
        // 0x60    | 0x60 0x50          | PUSH1 80       | 80 0                         //
        // 0x80    | 0x80               | DUP1           | 80 80 0                      //
        // 0x60    | 0x60 0x0b          | PUSH1 11       | 11 80 80 0                   //
        // 0x83    | 0x83               | DUP4           | 0 11 80 80 0                 //
        // 0x39    | 0x39               | CODECOPY       | 80 0                         //
        // 0x90    | 0x90               | SWAP1          | 0 80                         //
        // 0xf3    | 0xf3               | RETURN         |                              //
        //------------------------------------------------------------------------------//
        // deployed code (if caller != vaultProxyAdmin)                                 //
        // 0x60    | 0x60 0x00          | PUSH1 0        | 0                            //
        // 0x36    | 0x36               | CALLDATASIZE   | csize 0                      //
        // 0x81    | 0x81               | DUP2           | 0 csize 0                    //
        // 0x80    | 0x80               | DUP1           | 0 0 csize 0                  //
        // 0x37    | 0x37               | CALLDATACOPY   | 0                            //
        // 0x80    | 0x80               | DUP1           | 0 0                          //
        // 0x80    | 0x80               | DUP1           | 0 0 0                        //
        // 0x36    | 0x36               | CALLDATASIZE   | csize 0 0 0                  //
        // 0x81    | 0x81               | DUP2           | 0 csize 0 0 0                //
        // 0x33    | 0x33               | CALLER         | caller 0 csize 0 0 0         //
        // 0x73    | 0x73 proxyAdmin    | PUSH20 pAdmin  | pAdmin caller 0 csize 0 0 0  //
        // 0x14    | 0x14               | EQ             | false 0 csize 0 0 0          //
        // 0x60    | 0x60 0x2a          | PUSH1 42       | 42 false 0 csize 0 0 0       //
        // 0x57    | 0x57               | JUMPI          | 0 csize 0 0 0                //
        // 0x80    | 0x80               | DUP1           | 0 0 csize 0 0 0              //
        // 0x19    | 0x19               | NOT            | 0xffff..ffff 0 csize 0 0 0   //
        // 0x54    | 0x54               | SLOAD          | impl 0 csize 0 0 0           //
        // 0x60    | 0x60 0x40          | PUSH1 64       | 64 impl 0 csize 0 0 0        //
        // 0x56    | 0x56               | JUMP           | impl 0 csize 0 0 0           //
        // 0x5b    | 0x5b               | JUMPDEST       | impl 0 csize 0 0 0           //
        // 0x5a    | 0x5a               | GAS            | gas impl 0 csize 0 0 0       //
        // 0xf4    | 0xf4               | DELEGATECALL   | success 0                    //
        // 0x3d    | 0x3d               | RETURNDATASIZE | rsize success 0              //
        // 0x82    | 0x82               | DUP3           | 0 rsize success 0            //
        // 0x80    | 0x80               | DUP1           | 0 0 rsize success 0          //
        // 0x3e    | 0x3e               | RETURNDATACOPY | success 0                    //
        // 0x90    | 0x90               | SWAP1          | 0 success                    //
        // 0x3d    | 0x3d               | RETURNDATASIZE | rsize 0 success              //
        // 0x91    | 0x91               | SWAP2          | success 0 rsize              //
        // 0x60    | 0x60 0x4e          | PUSH1 78       | 78 success 0 rsize           //
        // 0x57    | 0x57               | JUMPI          | 0 rsize                      //
        // 0x5b    | 0x5b               | JUMPDEST       | 0 rsize                      //
        // 0xf3    | 0xf3               | RETURN         |                              //
        //------------------------------------------------------------------------------//

        // constructor returns runtime code
        //
        // runtime code:
        //   validate caller:
        //     1. If the caller is anyone other than `proxyAdmin` -> delegates call to`vaultImplementation`.
        //     2. If the caller is the `proxyAdmin` -> delegates call to `upgradeLogic`.
        return
            abi.encodePacked(
                hex"6000_6050_80_600b_83_39_90_f3_6000_36_81_80_37_80_80_36_81_33_73",
                vaultProxyAdmin,
                hex"14_602a_57_80_19_54_6040_56_5b_73",
                upgradeLogic,
                hex"5b_5a_f4_3d_82_80_3e_3d_82_82_604e_57_fd_5b_f3"
            );
    }
}

