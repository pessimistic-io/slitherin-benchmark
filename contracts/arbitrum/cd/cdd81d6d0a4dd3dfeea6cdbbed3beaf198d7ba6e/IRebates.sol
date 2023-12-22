// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

/**
 * @title IRebates
 * @notice Interface for Rebates
 */
interface IRebates {
    /**
     * @dev sets whether {rebater} can allocate rebates
     * @param rebater the address that can call rebates
     * @param canRebate whether or not {rebater} can rebate
     */
    function setCanInitiateRebate(address rebater, bool canRebate) external;

    /**
     * @dev sets the address that handles actions
     * @param action the id of the rebate action
     * @param handler the address of the contract that handles {action}
     */
    function setRebateHandler(bytes32 action, address handler) external;

    /**
     * @dev allocates rebates based on an arbitrary action / params
     * @param action the id of the rebate action
     * @param params the abi encoded parameters to pass to the handler
     */
    function initiateRebate(bytes32 action, bytes calldata params) external;

    /**
     * @dev creates a rebate of {amount} of {token} to {rebateReceiver}.
     * @param token the token to rebate to {rebateReceiver}
     * @param amount the amount of {token} to rebate to {rebateReceiver}
     * @param rebateReceiver the receiver of the rebate
     * @param action the action corresponding to this rebate
     */
    function registerRebate(
        address rebateReceiver,
        address token,
        uint256 amount,
        bytes32 action
    ) external;

    /**
     * @dev withdraws rebates of {token} to msg.sender
     * @param token the token to claim rebates for
     */
    function claim(address token) external;

    /**
     * @dev withdraws rebates of {token} to {receiver}
     * @param token the token to claim rebates for
     * @param receiver the receiver of the rebate
     */
    function claimFor(address token, address receiver) external;
}

