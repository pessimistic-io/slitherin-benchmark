// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;

/* solhint-disable avoid-low-level-calls */
/* solhint-disable no-inline-assembly */
/* solhint-disable reason-string */

// Base
import "./BaseAccount.sol";

// Fixed Extensions
import "./Multicall.sol";
import "./Initializable.sol";
import "./AccountPermissions.sol";

// Utils
import "./Helpers.sol";
import "./AccountCoreStorage.sol";
import "./BaseAccountFactory.sol";
import { AccountExtension } from "./AccountExtension.sol";
import "./ECDSA.sol";

import "./IAccountCore.sol";

//   $$\     $$\       $$\                 $$\                         $$\
//   $$ |    $$ |      \__|                $$ |                        $$ |
// $$$$$$\   $$$$$$$\  $$\  $$$$$$\   $$$$$$$ |$$\  $$\  $$\  $$$$$$\  $$$$$$$\
// \_$$  _|  $$  __$$\ $$ |$$  __$$\ $$  __$$ |$$ | $$ | $$ |$$  __$$\ $$  __$$\
//   $$ |    $$ |  $$ |$$ |$$ |  \__|$$ /  $$ |$$ | $$ | $$ |$$$$$$$$ |$$ |  $$ |
//   $$ |$$\ $$ |  $$ |$$ |$$ |      $$ |  $$ |$$ | $$ | $$ |$$   ____|$$ |  $$ |
//   \$$$$  |$$ |  $$ |$$ |$$ |      \$$$$$$$ |\$$$$$\$$$$  |\$$$$$$$\ $$$$$$$  |
//    \____/ \__|  \__|\__|\__|       \_______| \_____\____/  \_______|\_______/

contract AccountCore is IAccountCore, Initializable, Multicall, BaseAccount, AccountPermissions {
    using ECDSA for bytes32;
    using EnumerableSet for EnumerableSet.AddressSet;

    /*///////////////////////////////////////////////////////////////
                                State
    //////////////////////////////////////////////////////////////*/

    /// @notice EIP 4337 factory for this contract.
    address public immutable factory;

    /// @notice EIP 4337 Entrypoint contract.
    IEntryPoint private immutable entrypointContract;

    /*///////////////////////////////////////////////////////////////
                    Constructor, Initializer, Modifiers
    //////////////////////////////////////////////////////////////*/

    constructor(IEntryPoint _entrypoint, address _factory) EIP712("Account", "1") {
        _disableInitializers();
        factory = _factory;
        entrypointContract = _entrypoint;
    }

    /// @notice Initializes the smart contract wallet.
    function initialize(address _defaultAdmin, bytes calldata) public virtual initializer {
        // This is passed as data in the `_registerOnFactory()` call in `AccountExtension` / `Account`.
        AccountCoreStorage.data().firstAdmin = _defaultAdmin;
        _setAdmin(_defaultAdmin, true);
    }

    /*///////////////////////////////////////////////////////////////
                            View functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the EIP 4337 entrypoint contract.
    function entryPoint() public view virtual override returns (IEntryPoint) {
        address entrypointOverride = AccountCoreStorage.data().entrypointOverride;
        if (address(entrypointOverride) != address(0)) {
            return IEntryPoint(entrypointOverride);
        }
        return entrypointContract;
    }

    /// @notice Returns whether a signer is authorized to perform transactions using the wallet.
    function isValidSigner(address _signer, UserOperation calldata _userOp) public view virtual returns (bool) {
        // First, check if the signer is an admin.
        if (_accountPermissionsStorage().isAdmin[_signer]) {
            return true;
        }

        SignerPermissionsStatic memory permissions = _accountPermissionsStorage().signerPermissions[_signer];

        // If not an admin, check if the signer is active.
        if (
            permissions.startTimestamp > block.timestamp ||
            block.timestamp >= permissions.endTimestamp ||
            _accountPermissionsStorage().approvedTargets[_signer].length() == 0
        ) {
            // Account: no active permissions.
            return false;
        }

        // Extract the function signature from the userOp calldata and check whether the signer is attempting to call `execute` or `executeBatch`.
        bytes4 sig = getFunctionSignature(_userOp.callData);

        if (sig == AccountExtension.execute.selector) {
            // Extract the `target` and `value` arguments from the calldata for `execute`.
            (address target, uint256 value) = decodeExecuteCalldata(_userOp.callData);

            // Check if the value is within the allowed range and if the target is approved.
            if (
                permissions.nativeTokenLimitPerTransaction < value ||
                !_accountPermissionsStorage().approvedTargets[_signer].contains(target)
            ) {
                // Account: value too high OR Account: target not approved.
                return false;
            }
        } else if (sig == AccountExtension.executeBatch.selector) {
            // Extract the `target` and `value` array arguments from the calldata for `executeBatch`.
            (address[] memory targets, uint256[] memory values, ) = decodeExecuteBatchCalldata(_userOp.callData);

            // For each target+value pair, check if the value is within the allowed range and if the target is approved.
            for (uint256 i = 0; i < targets.length; i++) {
                if (
                    permissions.nativeTokenLimitPerTransaction < values[i] ||
                    !_accountPermissionsStorage().approvedTargets[_signer].contains(targets[i])
                ) {
                    // Account: value too high OR Account: target not approved.
                    return false;
                }
            }
        } else {
            // Account: calling invalid fn.
            return false;
        }

        return true;
    }

    /*///////////////////////////////////////////////////////////////
                            External functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit funds for this account in Entrypoint.
    function addDeposit() public payable {
        entryPoint().depositTo{ value: msg.value }(address(this));
    }

    /// @notice Withdraw funds for this account from Entrypoint.
    function withdrawDepositTo(address payable withdrawAddress, uint256 amount) public onlyAdmin {
        entryPoint().withdrawTo(withdrawAddress, amount);
    }

    /// @notice Overrides the Entrypoint contract being used.
    function setEntrypointOverride(IEntryPoint _entrypointOverride) public virtual onlyAdmin {
        AccountCoreStorage.data().entrypointOverride = address(_entrypointOverride);
    }

    /*///////////////////////////////////////////////////////////////
                        Internal functions
    //////////////////////////////////////////////////////////////*/

    function getFunctionSignature(bytes calldata data) internal pure returns (bytes4 functionSelector) {
        require(data.length >= 4, "Data too short");
        return bytes4(data[:4]);
    }

    function decodeExecuteCalldata(bytes calldata data) internal pure returns (address _target, uint256 _value) {
        require(data.length >= 4 + 32 + 32, "Data too short");

        // Decode the address, which is bytes 4 to 35
        _target = abi.decode(data[4:36], (address));

        // Decode the value, which is bytes 36 to 68
        _value = abi.decode(data[36:68], (uint256));
    }

    function decodeExecuteBatchCalldata(bytes calldata data)
        internal
        pure
        returns (
            address[] memory _targets,
            uint256[] memory _values,
            bytes[] memory _callData
        )
    {
        require(data.length >= 4 + 32 + 32 + 32, "Data too short");

        (_targets, _values, _callData) = abi.decode(data[4:], (address[], uint256[], bytes[]));
    }

    /// @notice Validates the signature of a user operation.
    function _validateSignature(UserOperation calldata userOp, bytes32 userOpHash)
        internal
        virtual
        override
        returns (uint256 validationData)
    {
        bytes32 hash = userOpHash.toEthSignedMessageHash();
        address signer = hash.recover(userOp.signature);

        if (!isValidSigner(signer, userOp)) return SIG_VALIDATION_FAILED;

        uint48 validAfter = uint48(_accountPermissionsStorage().signerPermissions[signer].startTimestamp);
        uint48 validUntil = uint48(_accountPermissionsStorage().signerPermissions[signer].endTimestamp);

        return _packValidationData(ValidationData(address(0), validAfter, validUntil));
    }

    /// @notice Makes the given account an admin.
    function _setAdmin(address _account, bool _isAdmin) internal virtual override {
        super._setAdmin(_account, _isAdmin);
        if (factory.code.length > 0) {
            if (_isAdmin) {
                BaseAccountFactory(factory).onSignerAdded(_account, AccountCoreStorage.data().firstAdmin, "");
            } else {
                BaseAccountFactory(factory).onSignerRemoved(_account, AccountCoreStorage.data().firstAdmin, "");
            }
        }
    }

    /// @notice Runs after every `changeRole` run.
    function _afterSignerPermissionsUpdate(SignerPermissionRequest calldata _req) internal virtual override {
        if (factory.code.length > 0) {
            BaseAccountFactory(factory).onSignerAdded(_req.signer, AccountCoreStorage.data().firstAdmin, "");
        }
    }
}

