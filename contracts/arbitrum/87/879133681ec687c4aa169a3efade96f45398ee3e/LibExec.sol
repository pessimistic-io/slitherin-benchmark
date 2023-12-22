// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {EnumerableSet} from "./EnumerableSet.sol";

library LibExec {
    using EnumerableSet for EnumerableSet.AddressSet;

    struct ExecutorStorage {
        EnumerableSet.AddressSet executors;
    }

    bytes32 private constant _EXECUTOR_STORAGE_POSITION =
        keccak256("gelato.diamond.executor.storage");

    function addExecutor(address _executor) internal returns (bool) {
        return executorStorage().executors.add(_executor);
    }

    function removeExecutor(address _executor) internal returns (bool) {
        return executorStorage().executors.remove(_executor);
    }

    function canExec(address _executor) internal view returns (bool) {
        return isExecutor(_executor);
    }

    function isExecutor(address _executor) internal view returns (bool) {
        return executorStorage().executors.contains(_executor);
    }

    function executorAt(uint256 _index) internal view returns (address) {
        return executorStorage().executors.at(_index);
    }

    function executors() internal view returns (address[] memory executors_) {
        uint256 length = numberOfExecutors();
        executors_ = new address[](length);
        for (uint256 i; i < length; i++) executors_[i] = executorAt(i);
    }

    function numberOfExecutors() internal view returns (uint256) {
        return executorStorage().executors.length();
    }

    function executorStorage()
        internal
        pure
        returns (ExecutorStorage storage es)
    {
        bytes32 position = _EXECUTOR_STORAGE_POSITION;
        assembly {
            es.slot := position
        }
    }
}

