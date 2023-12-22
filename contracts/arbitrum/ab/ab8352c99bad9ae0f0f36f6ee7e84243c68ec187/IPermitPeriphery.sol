// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./ICore.sol";

interface IPermitPeriphery {
    struct Permit {
        uint256 value;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    function acceptWithPermit(
        ICore core,
        ICore.Accept[] memory data,
        Permit memory permit
    ) external returns (uint256[] memory positionIds);
    function createOrderWithPermit(
        ICore core,
        ICore.OrderDescription memory data,
        uint256 amount,
        Permit memory permit
    ) external returns (uint256);
    function increaseOrderWithPermit(
        ICore core,
        uint256 orderId,
        uint256 amount,
        Permit memory permit
    ) external returns (bool);
}

