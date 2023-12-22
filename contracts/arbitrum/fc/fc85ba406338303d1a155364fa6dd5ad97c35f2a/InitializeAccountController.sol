// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC6551Registry} from "./ERC6551Registry.sol";
import {IERC6551AccountInitializer} from "./IERC6551AccountInitializer.sol";
import {IPermissions} from "./IPermissions.sol";
import {Operations} from "./Operations.sol";
import {PermitController} from "./PermitController.sol";

/// @notice Bundle account creation and initialization into one transaction
contract InitializeAccountController is PermitController {
    error InvalidPermission();

    /// @notice Core function to bundle together account deployment and initialization
    /// @dev usePermits is added to allow dynamic permissioning via direct call or signature permit from
    /// an entity with INITIALIZE_ACCOUNT_PERMIT permission on the account group
    function createAndInitializeAccount(
        address registry,
        address accountProxy,
        bytes32 salt,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId,
        address accountImpl,
        bytes memory initData
    ) external usePermits(_encodePermitContext(salt)) returns (address account) {
        // deploy account
        account = IERC6551Registry(registry).createAccount(accountProxy, salt, chainId, tokenContract, tokenId);
        // initialize account
        IERC6551AccountInitializer(account).initializeAccount(accountImpl, initData);
    }

    /*===================
        AUTHORIZATION
    ===================*/

    function _encodePermitContext(bytes32 salt) internal pure returns (bytes memory context) {
        return abi.encode(salt);
    }

    function _decodePermitContext(bytes memory context) internal pure returns (address accountGroup) {
        return address(bytes20(abi.decode(context, (bytes32))));
    }

    /// @notice If sender has INITIALIZE_ACCOUNT_PERMIT permission on account group, then skip permit process
    function requirePermits(bytes memory context) public view override returns (bool) {
        address accountGroup = _decodePermitContext(context);
        return !IPermissions(accountGroup).hasPermission(Operations.INITIALIZE_ACCOUNT_PERMIT, msg.sender);
    }

    /// @notice If a permit is expected, then validate the signer has INITIALIZE_ACCOUNT_PERMIT permission
    function signerCanPermit(address signer, bytes memory context) public view override returns (bool) {
        address accountGroup = _decodePermitContext(context);
        return IPermissions(accountGroup).hasPermission(Operations.INITIALIZE_ACCOUNT_PERMIT, signer);
    }
}

