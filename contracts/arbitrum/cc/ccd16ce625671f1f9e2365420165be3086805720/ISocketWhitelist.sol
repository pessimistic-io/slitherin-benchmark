// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

/**
 * @title ISocketWhitelist
 * @notice Interface for Socket Whitelisting Contract.
 * @author reddyismav.
 */
interface ISocketWhitelist {
    // --------------------------------------------------------- RFQ SOLVERS --------------------------------------------------- //
    function addRFQSolver(address _solverAddress) external;

    function disableRFQSolver(address _solverAddress) external;

    function isRFQSolver(address _solverAddress) external view returns (bool);

    // --------------------------------------------------------- GATEWAY SOLVERS --------------------------------------------------- //
    function addGatewaySolver(address _solverAddress) external;

    function disableGatewaySolver(address _solverAddress) external;

    function isGatewaySolver(
        address _solverAddress
    ) external view returns (bool);

    // --------------------------------------------------------- SOCKET SIGNERS --------------------------------------------------- //
    function addSignerAddress(address _signerAddress) external;

    function disableSignerAddress(address _signerAddress) external;

    function isSigner(address _signerAddress) external view returns (bool);

    function isSocketApproved(
        bytes32 _messageHash,
        bytes calldata _sig
    ) external view returns (bool);
}

