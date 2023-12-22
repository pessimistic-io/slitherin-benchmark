// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import "./AccessControl.sol";
import "./ERC20_IERC20.sol";
import "./CircomData.sol";
import "./ITransactHook.sol";
import "./Transferer.sol";
import "./HinkalBase.sol";

abstract contract HinkalMigrator is ITransactHook, AccessControl {
    struct MigrateData {
        uint256 shieldedPublicKey;
        uint256 blinding;
        bytes encryptedOutput;
    }

    bytes32 public constant OLD_HINKAL_ROLE = keccak256("OLD_HINKAL_ROLE");

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function afterTransact(
        CircomData memory circomData,
        bytes calldata metadata
    ) external onlyRole(OLD_HINKAL_ROLE) {
        require(circomData.publicAmount < 0, "Only withdrawals supported");
        require(circomData.recipientAddress == address(this), "Target of withdrawal should be this contract");

        MigrateData memory migrateData = parseMetadata(metadata);
        migrate(circomData, migrateData);
    }

    function parseMetadata(bytes memory metadata) internal returns (MigrateData memory) {
        return abi.decode(metadata, (MigrateData));
    }

    function migrate(CircomData memory circomData, MigrateData memory migrateData) internal virtual;
}

