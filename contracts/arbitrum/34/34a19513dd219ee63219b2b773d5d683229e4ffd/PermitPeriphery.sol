// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./IPermitPeriphery.sol";

contract PermitPeriphery is IPermitPeriphery {
    function acceptWithPermit(
        ICore core,
        uint256 orderId,
        uint256 amount,
        Permit memory permit
    ) external returns (uint256) {
        (,,,IERC20Stable stable) = core.configuration().immutableConfiguration();
        stable.permit(
            msg.sender,
            address(this),
            permit.value,
            permit.deadline,
            permit.v,
            permit.r,
            permit.s
        );
        stable.transferFrom(msg.sender, address(this), amount);
        stable.approve(address(core), amount);
        return core.accept(msg.sender, orderId, amount);
    }

    function createOrderWithPermit(
        ICore core,
        ICore.OrderDescription memory data,
        uint256 amount,
        Permit memory permit
    ) external returns (uint256) {
        (,,,IERC20Stable stable) = core.configuration().immutableConfiguration();
        stable.permit(
            msg.sender,
            address(this),
            permit.value,
            permit.deadline,
            permit.v,
            permit.r,
            permit.s
        );
        stable.transferFrom(msg.sender, address(this), amount);
        stable.approve(address(core), amount);
        return core.createOrder(msg.sender, data, amount);
    }
}

