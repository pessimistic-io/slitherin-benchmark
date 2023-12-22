// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import {ECDSAUpgradeable} from "./ECDSAUpgradeable.sol";
import {AddressUpgradeable} from "./AddressUpgradeable.sol";
import {EIP712Upgradeable} from "./EIP712Upgradeable.sol";

import {IGaslessSmartWallet} from "./IGaslessSmartWallet.sol";

error GaslessSmartWallet__InvalidParams();
error GaslessSmartWallet__InvalidSignature();
error GaslessSmartWallet__Expired();

/// @title  GaslessSmartWallet
/// @notice Implements meta transactions, partially aligned with EIP2770 and according to EIP712 signature
///         The `cast` method allows the owner of the wallet to execute multiple arbitrary actions
///         Relayers are expected to call the forwarder contract `execute`, which deploys a Gasless Smart Wallet if necessary first
/// @dev    This contract implements parts of EIP-2770 in a minimized form. E.g. domainSeparator is immutable etc.
///         This contract does not implement ERC2771, because trusting an upgradeable "forwarder"
///         bears a security risk for this non-custodial wallet
///         This contract validates all signatures for defaultChainId of 420 instead of current block.chainid from opcode (EIP-1344)
///         For replay protection, the current block.chainid instead is used in the EIP-712 salt
contract GaslessSmartWallet is EIP712Upgradeable, IGaslessSmartWallet {
    using AddressUpgradeable for address;

    /***********************************|
    |             CONSTANTS             |
    |__________________________________*/

    // constants for EIP712 values
    string public constant domainSeparatorName =
        "Instadapp-Gasless-Smart-Wallet";
    string public constant domainSeparatorVersion = "1.0.0";
    // chain id for EIP712 is always set to 420
    uint256 public constant defaultChainId = 420;
    // _TYPE_HASH is copied from EIP712Upgradeable but with added salt as last param (we use it for block.chainid)
    bytes32 private constant _TYPE_HASH =
        keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)"
        );

    // keccak256 of "Cast(address[] targets,bytes[] datas,uint256[] values,uint256 gswNonce,uint256 validUntil,uint256 gas)";
    bytes32 public constant castTypeHash =
        0x5724a3a07dca5caa43ce8bf390a182a24c7474444b5689954cdc22693214ac64;

    /***********************************|
    |           STATE VARIABLES         |
    |__________________________________*/

    /// @notice owner of the smart wallet
    /// @dev theoretically immutable, can only be set in initialize (at proxy clone factory deployment)
    address public owner;

    /// @notice nonce that it is incremented for every `cast` transaction with valid signature
    uint256 public gswNonce;

    /***********************************|
    |               EVENTS              |
    |__________________________________*/

    event CastExecuted();
    event CastFailed(string reason, address target, bytes data, uint256 value);

    /***********************************|
    |    CONSTRUCTOR / INITIALIZERS     |
    |__________________________________*/

    constructor() {
        // Ensure logic contract initializer is not abused by disabling initializing
        // see https://forum.openzeppelin.com/t/security-advisory-initialize-uups-implementation-contracts/15301
        // and https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable#initializing_the_implementation_contract
        _disableInitializers();
    }

    /// @inheritdoc IGaslessSmartWallet
    function initialize(address _owner) public initializer {
        // owner must be EOA
        if (_owner.isContract()) {
            revert GaslessSmartWallet__InvalidParams();
        }

        __EIP712_init(domainSeparatorName, domainSeparatorVersion);

        owner = _owner;
    }

    /***********************************|
    |            PUBLIC API             |
    |__________________________________*/

    receive() external payable {}

    /// @inheritdoc IGaslessSmartWallet
    function domainSeparatorV4() public view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @inheritdoc IGaslessSmartWallet
    function verify(
        address[] calldata targets,
        bytes[] calldata datas,
        uint256[] calldata values,
        bytes calldata signature,
        uint256 validUntil,
        uint256 gas
    ) external view returns (bool) {
        // Do not use modifiers to avoid stack too deep
        {
            _validateParams(targets, datas, values, validUntil);
        }
        {
            if (
                !_verifySig(targets, datas, values, validUntil, gas, signature)
            ) {
                revert GaslessSmartWallet__InvalidSignature();
            }
        }
        return true;
    }

    /// @inheritdoc IGaslessSmartWallet
    function cast(
        address[] calldata targets,
        bytes[] calldata datas,
        uint256[] calldata values,
        bytes calldata signature,
        uint256 validUntil,
        uint256 gas
    ) external payable {
        // Do not use modifiers to avoid stack too deep
        {
            _validateParams(targets, datas, values, validUntil);
        }
        {
            if (
                // cast can be called through forwarder with signature or directly by the owner
                msg.sender != owner &&
                !_verifySig(targets, datas, values, validUntil, gas, signature)
            ) {
                revert GaslessSmartWallet__InvalidSignature();
            }
        }

        // nonce increases *always* if signature is valid
        gswNonce++;

        _callTargets(targets, datas, values);

        // Logic below based on MinimalForwarderUpgradeable from openzeppelin:
        // (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/metatx/MinimalForwarder.sol)
        // Validate that the relayer has sent enough gas for the call.
        // See https://ronan.eth.limo/blog/ethereum-gas-dangers/
        if (gasleft() <= gas / 63) {
            // We explicitly trigger invalid opcode to consume all gas and bubble-up the effects, since
            // neither revert or assert consume all gas since Solidity 0.8.0
            // https://docs.soliditylang.org/en/v0.8.0/control-structures.html#panic-via-assert-and-error-via-require
            /// @solidity memory-safe-assembly
            assembly {
                invalid()
            }
        }
    }

    /***********************************|
    |              INTERNAL             |
    |__________________________________*/

    function _callTargets(
        address[] calldata targets,
        bytes[] calldata datas,
        uint256[] calldata values
    ) internal {
        for (uint256 i = 0; i < targets.length; ++i) {
            if (values[i] != 0) {
                if (address(this).balance < values[i]) {
                    emit CastFailed(
                        "GSW__INSUFFICIENT_VALUE",
                        targets[i],
                        datas[i],
                        values[i]
                    );

                    return;
                }
            }

            // try catch does not work for .call
            (bool success, bytes memory result) = targets[i].call{
                value: values[i]
            }(datas[i]);

            if (!success) {
                // get revert reason if available, based on https://ethereum.stackexchange.com/a/83577
                // as used by uniswap (https://github.com/Uniswap/v3-periphery/blob/main/contracts/base/Multicall.sol)
                if (result.length > 68) {
                    assembly {
                        result := add(result, 0x04)
                    }
                    string memory revertReason = abi.decode(result, (string));
                    emit CastFailed(
                        revertReason,
                        targets[i],
                        datas[i],
                        values[i]
                    );
                } else {
                    emit CastFailed("", targets[i], datas[i], values[i]);
                }

                // stop executing any more actions but do not revert
                return;
            }
        }

        emit CastExecuted();
    }

    function _verifySig(
        address[] calldata targets,
        bytes[] calldata datas,
        uint256[] calldata values,
        uint256 validUntil,
        uint256 gas,
        bytes calldata signature
    ) internal view returns (bool) {
        bytes32[] memory keccakDatas = new bytes32[](datas.length);
        for (uint256 i = 0; i < datas.length; i++) {
            keccakDatas[i] = keccak256(datas[i]);
        }

        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    castTypeHash,
                    keccak256(abi.encodePacked(targets)),
                    keccak256(abi.encodePacked(keccakDatas)),
                    keccak256(abi.encodePacked(values)),
                    gswNonce,
                    validUntil,
                    gas
                )
            )
        );
        address recoveredSigner = ECDSAUpgradeable.recover(digest, signature);

        return recoveredSigner == owner;
    }

    function _validateParams(
        address[] calldata targets,
        bytes[] calldata datas,
        uint256[] calldata values,
        uint256 validUntil
    ) internal view {
        if (
            targets.length == 0 ||
            targets.length != datas.length ||
            targets.length != values.length
        ) {
            revert GaslessSmartWallet__InvalidParams();
        }

        // make sure request is still valid
        if (validUntil != 0 && validUntil < block.timestamp) {
            revert GaslessSmartWallet__Expired();
        }
    }

    /// @inheritdoc EIP712Upgradeable
    /// @dev same as _hashTypedDataV4 but calls _domainSeparatorV4Override instead
    /// to build for chain id 420 and block.chainid in salt
    function _hashTypedDataV4(bytes32 structHash)
        internal
        view
        override
        returns (bytes32)
    {
        return
            ECDSAUpgradeable.toTypedDataHash(
                _domainSeparatorV4Override(),
                structHash
            );
    }

    /// @notice Returns the domain separator for the chain with id 420.
    /// @dev can not override EIP712 _domainSeparatorV4 directly because it is not marked as virtual
    /// same as EIP712 _domainSeparatorV4 but calls _buildDomainSeparatorOverride instead
    /// to build for chain id 420 and block.chainid in salt
    function _domainSeparatorV4Override() internal view returns (bytes32) {
        return
            _buildDomainSeparatorOverride(
                _TYPE_HASH,
                _EIP712NameHash(),
                _EIP712VersionHash()
            );
    }

    /// @notice builds domain separator for EIP712 but with fixed chain id set to 420 instead of current chain
    /// @dev can not override EIP712 _buildDomainSeparator directly because it is not marked as virtual
    /// sets defaultChainId (420) instead of block.chainid for the hash, uses block.chainid in salt
    function _buildDomainSeparatorOverride(
        bytes32 typeHash,
        bytes32 nameHash,
        bytes32 versionHash
    ) internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    typeHash,
                    nameHash,
                    versionHash,
                    defaultChainId,
                    address(this),
                    keccak256(abi.encodePacked(block.chainid))
                )
            );
    }
}

