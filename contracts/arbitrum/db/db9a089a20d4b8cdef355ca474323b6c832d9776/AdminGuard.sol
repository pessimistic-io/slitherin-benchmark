// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity >=0.7.0 <0.9.0;

import {Enum} from "./Enum.sol";
import {BaseGuard} from "./GuardManager.sol";
import {OwnerManager} from "./OwnerManager.sol";
import {ModuleManager} from "./ModuleManager.sol";
import {Safe} from "./Safe.sol";
import {StorageAccessible} from "./StorageAccessible.sol";

/// @title AdminGuard
/// @author 👦🏻👦🏻.eth
/// @dev This guard contract limits delegate calls to two immutable targets
/// and uses hook mechanisms to prevent Modules from altering sensitive state variables

contract AdminGuard is BaseGuard {
    address public constant ALLOWED_MULTICALL3 = 0xcA11bde05977b3631167028862bE2a173976CA11;

    fallback() external {
        // We don't revert on fallback to avoid issues in case of a Safe upgrade
        // E.g. The expected check method might change and then the Safe would be locked.
    }

    /**
     * @notice Called by the Safe contract before a transaction is executed.
     * @dev  Reverts if the transaction is a delegate call to contract other than the allowed one.
     * @param to Destination address of Safe transaction.
     * @param operation Operation type of Safe transaction.
     */
    function checkTransaction(
        address to,
        uint256,
        bytes memory,
        Enum.Operation operation,
        uint256,
        uint256,
        uint256,
        address,
        address payable,
        bytes memory,
        address
    ) external pure override {
        require(operation != Enum.Operation.DelegateCall || to == ALLOWED_MULTICALL3, "RESTRICTED");
    }

    function checkAfterExecution(bytes32 stateHash, bool) external view override {
        require(stateHash == _hashSafeSensitiveState(), "STATE_VIOLATION");
    }

    /**
     * @notice Called by the Safe contract before a transaction is executed via a module.
     * @param to Destination address of Safe transaction.
     * @param '' Ether value of Safe transaction.
     * @param '' Data payload of Safe transaction.
     * @param operation Operation type of Safe transaction.
     * @param '' Module executing the transaction.
     */
    function checkModuleTransaction(address to, uint256, bytes memory, Enum.Operation operation, address)
        external
        view
        override
        returns (bytes32 stateHash)
    {
        require(operation != Enum.Operation.DelegateCall || to == ALLOWED_MULTICALL3, "RESTRICTED");

        stateHash = _hashSafeSensitiveState();
    }

    function _hashSafeSensitiveState() internal view returns (bytes32) {
        // get sensitive state which should not be mutated by modules using public functions wherever possible and `getStorageAt()` when not
        address singleton = address(uint160(uint256(bytes32(StorageAccessible(msg.sender).getStorageAt(0, 1)))));

        // keccak256("fallback_manager.handler.address");
        bytes32 fallbackHandlerSlot = 0x6c9a6c4a39284e37ed1cf53d337577d14212a4870fb976a4366c693b939918d5;
        address fallbackHandler = address(
            uint160(uint256(bytes32(StorageAccessible(msg.sender).getStorageAt(uint256(fallbackHandlerSlot), 1))))
        );

        // keccak256("guard_manager.guard.address");
        bytes32 guardStorageSlot = 0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8;
        address guard =
            address(uint160(uint256(bytes32(StorageAccessible(msg.sender).getStorageAt(uint256(guardStorageSlot), 1)))));

        (address[] memory modules, address sentinelModulesLimiter) = ModuleManager(msg.sender).getModulesPaginated(address(0x1), 32);

        address[] memory owners = OwnerManager(msg.sender).getOwners();
        uint256 ownerCountSlot = 4;
        uint256 ownerCount = uint256(bytes32(StorageAccessible(msg.sender).getStorageAt(ownerCountSlot, 1)));

        uint256 threshold = OwnerManager(msg.sender).getThreshold();
        uint256 nonce = Safe(payable(msg.sender)).nonce();

        return keccak256(
            abi.encodePacked(singleton, fallbackHandler, guard, modules, sentinelModulesLimiter, owners, ownerCount, threshold, nonce)
        );
    }
}

