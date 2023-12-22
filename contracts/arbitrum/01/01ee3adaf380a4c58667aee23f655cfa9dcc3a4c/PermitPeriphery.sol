// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./IPermitPeriphery.sol";

/**
 * @title PermitPeriphery
 * @notice This smart contract implements methods for working with orders and positions using a permit.
 */
contract PermitPeriphery is IPermitPeriphery {
    /**
     * @notice Allows a user to accept an order using permit signatures.
     * @param core The address of the core contract.
     * @param data The Accept struct containing the amount and orderId.
     * @param permit A struct containing the permit signature data.
     * @return positionIds The IDs of the created positions.
     */
    function acceptWithPermit(
        ICore core,
        ICore.Accept[] memory data,
        Permit memory permit
    ) external returns (uint256[] memory positionIds) {
        for (uint256 i = 0; i < data.length; i++) {
            (, , , IERC20Stable stable) = core.configuration().immutableConfiguration();
            stable.permit(msg.sender, address(this), permit.value, permit.deadline, permit.v, permit.r, permit.s);
            stable.transferFrom(msg.sender, address(this), data[i].amount);
            stable.approve(address(core), data[i].amount);
            positionIds = core.accept(msg.sender, data);
        }
    }

    /**
     * @notice Allows a user to create an order using permit signatures.
     * @param core The address of the core contract.
     * @param data A struct containing the order details.
     * @param amount The amount of tokens being transferred.
     * @param permit A struct containing the permit signature data.
     * @return The ID of the created order.
     */
    function createOrderWithPermit(
        ICore core,
        ICore.OrderDescription memory data,
        uint256 amount,
        Permit memory permit
    ) external returns (uint256) {
        (, , , IERC20Stable stable) = core.configuration().immutableConfiguration();
        stable.permit(msg.sender, address(this), permit.value, permit.deadline, permit.v, permit.r, permit.s);
        stable.transferFrom(msg.sender, address(this), amount);
        stable.approve(address(core), amount);
        return core.createOrder(msg.sender, data, amount);
    }

    /**
     * @notice Allows a user to increase an order using permit signatures.
     * @param core The address of the core contract.
     * @param orderId The ID of the order being increased.
     * @param amount The amount of tokens being transferred.
     * @param permit A struct containing the permit signature data.
     * @return A boolean indicating whether the order was successfully increased.
     */
    function increaseOrderWithPermit(
        ICore core,
        uint256 orderId,
        uint256 amount,
        Permit memory permit
    ) external returns (bool) {
        (, , , IERC20Stable stable) = core.configuration().immutableConfiguration();
        stable.permit(msg.sender, address(this), permit.value, permit.deadline, permit.v, permit.r, permit.s);
        stable.transferFrom(msg.sender, address(this), amount);
        stable.approve(address(core), amount);
        return core.increaseOrder(orderId, amount);
    }
}

