/**
 * Base logic for the vault operations queue,
 * which enables queueing on operations locks, for a robust working
 * system even with offchain interverience
 */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "./Schema.sol";

abstract contract OperationsQueue is IVault {
    // ==============================
    //      OPERATIONS MANAGER
    // ==============================

    /**
     * @dev An array keeping track of the operation requests
     */
    OperationItem[] internal operationRequests;

    function getOperationItem(
        uint256 idx
    ) external view returns (OperationItem memory opItem) {
        opItem = operationRequests[idx];
    }

    function getOperationRequests()
        external
        view
        returns (OperationItem[] memory reqs)
    {
        reqs = operationRequests;
    }

    /**
     * @notice
     * @dev
     * Request an operation run.
     * An operation may be a deposit, withdraw, or a strategy run.
     * @param operationItem - the operation item to push.
     */
    function requestOperation(OperationItem memory operationItem) internal {
        // We push the operation item into our requests array
        operationRequests.push(operationItem);

        /**
         * @notice
         * We emit a "HydrateRun" event to hydrate our operation item.
         * The offchain handler will find it in storage (based on our provided index), retreive
         * the required command calldatas (if any) using simulations and offchain computation,
         * and reenter this contract in order to execute it
         */
        emit HydrateRun(operationRequests.length - 1);
    }
}

