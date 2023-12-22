// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

/**
 * @title IPReceiver
 * @author pNetwork
 *
 * @notice
 */
interface IPReceiver {
    /*
     * @notice Function called when userData.length > 0 within PNetworkHub.protocolExecuteOperation.
     *
     * @param userData
     */
    function receiveUserData(bytes calldata userData) external;
}

