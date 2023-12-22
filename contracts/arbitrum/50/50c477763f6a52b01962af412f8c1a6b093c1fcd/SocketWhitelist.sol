// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Ownable} from "./Ownable.sol";
import {AuthenticationLib} from "./AuthenticationLib.sol";

// TODO - Do we need different signers for different extractors. I think we do not need. But keeping it as todo.
/**
 * @title SocketSigner
 * @notice Handle all socket signer address whitelist
 * @dev All Batch orders will be signed by socket gateway signers, only then they will be executable
 * @author reddyismav.
 */
contract SocketWhitelist is Ownable {
    /// @notice owner owner of the contract
    constructor(address _owner) Ownable(_owner) {}

    // --------------------------------------------------- MAPPINGS -------------------------------------------------- //

    /// @notice Socket signer that signs against the order thats submitted.
    mapping(address => bool) socketSigners;

    /// @notice Socket solvers are the addresses that have the execution rights for user orders.
    mapping(address => bool) public gatewaySolvers;

    /// @notice Socket solvers are the addresses that have the execution rights for user orders.
    mapping(address => bool) public rfqSolvers;

    // -------------------------------------------------- SOCKET SIGNER ADMIN FUNCTIONS -------------------------------------------------- //

    /**
     * @notice Set Signer Addresses.
     * @param _signerAddress address that can sign against a batch.
     */
    function addSignerAddress(address _signerAddress) external onlyOwner {
        socketSigners[_signerAddress] = true;
    }

    /**
     * @notice Disbale Signer Address.
     * @param _signerAddress address that can sign against a batch.
     */
    function disableSignerAddress(address _signerAddress) external onlyOwner {
        socketSigners[_signerAddress] = false;
    }

    // -------------------------------------------------- GATEWAY SOLVERS ADMIN FUNCTIONS -------------------------------------------------- //

    /**
     * @notice Set Solver Address.
     * @param _solverAddress address that has the right to execute a user order.
     */
    function addGatewaySolver(address _solverAddress) external onlyOwner {
        gatewaySolvers[_solverAddress] = true;
    }

    /**
     * @notice Disbale Solver Address.
     * @param _solverAddress address that has the right to execute a user order.
     */
    function disableGatewaySolver(address _solverAddress) external onlyOwner {
        gatewaySolvers[_solverAddress] = false;
    }

    // -------------------------------------------------- RFQ SOLVERS ADMIN FUNCTIONS -------------------------------------------------- //

    /**
     * @notice Set Solver Address.
     * @param _solverAddress address that has the right to execute a user order.
     */
    function addRFQSolver(address _solverAddress) external onlyOwner {
        rfqSolvers[_solverAddress] = true;
    }

    /**
     * @notice Disbale Solver Address.
     * @param _solverAddress address that has the right to execute a user order.
     */
    function disableRFQSolver(address _solverAddress) external onlyOwner {
        rfqSolvers[_solverAddress] = false;
    }

    // -------------------------------------------------- SOCKET SIGNER VIEW FUNCTIONS -------------------------------------------------- //

    /**
     * @notice Check if an messageHash has been approved by Socket
     * @param _messageHash messageHash that has been signed by a socket signer
     * @param _sig is the signature produced by socket signer
     */
    function isSocketApproved(
        bytes32 _messageHash,
        bytes calldata _sig
    ) public view returns (bool) {
        return
            socketSigners[AuthenticationLib.authenticate(_messageHash, _sig)];
    }

    /**
     * @notice Check if an address is a socket permitted signer address.
     * @param _signerAddress address that can sign against a batch.
     */
    function isSigner(address _signerAddress) public view returns (bool) {
        return socketSigners[_signerAddress];
    }

    // -------------------------------------------------- GATEWAY SOLVERS VIEW FUNCTIONS -------------------------------------------------- //

    /**
     * @notice Check if the address given is a Gateway Solver..
     * @param _solverAddress address that has the right to execute a user order.
     */
    function isGatewaySolver(
        address _solverAddress
    ) public view returns (bool) {
        return gatewaySolvers[_solverAddress];
    }

    // -------------------------------------------------- RFQ SOLVERS VIEW FUNCTIONS -------------------------------------------------- //

    /**
     * @notice Check if the address given is a RFQ Solver..
     * @param _solverAddress address that has the right to execute a user order.
     */
    function isRFQSolver(address _solverAddress) public view returns (bool) {
        return rfqSolvers[_solverAddress];
    }
}

