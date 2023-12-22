// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "./Enum.sol";

interface IAvaultGuard {
    event OperationBlocked(string _reason);

    function checkTransaction(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    ) external view returns (bool);
}
