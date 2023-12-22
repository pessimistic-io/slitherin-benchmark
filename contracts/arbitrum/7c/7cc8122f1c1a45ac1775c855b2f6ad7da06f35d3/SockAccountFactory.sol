// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import "./Create2.sol";
import "./ERC1967Proxy.sol";

import "./SockAccount.sol";

/**
 * @title SockAccountFactory
 * @dev Factory contract to create and manage SockAccount proxy instances.
 */
contract SockAccountFactory {
    // Immutable reference to the account implementation contract
    SockAccount public immutable accountImplementation;

    // Event to be emitted upon SockAccount creation
    event SockAccountCreated(address);

    /**
     * @dev Constructor to create an instance of the SockAccount implementation contract.
     * @param _entryPoint A reference to an EntryPoint contract.
     */
    constructor(IEntryPoint _entryPoint) {
        accountImplementation = new SockAccount(_entryPoint);
    }

    /**
     * @notice Creates a new account (if it doesn't exist) and returns its address.
     * If the account already exists, simply returns its address.
     * @param aSockFunctionRegistry Reference to a SockFunctionRegistry contract.
     * @param anOwner Address of the owner of the SockAccount.
     * @param aSockOwner Address of the sockOwner of the SockAccount.
     * @param salt A salt value to generate a unique address for the new SockAccount.
     * @return ret The address of the created (or existing) SockAccount.
     */
    function createAccount(
        ISockFunctionRegistry aSockFunctionRegistry,
        address anOwner,
        address aSockOwner,
        uint256 salt
    ) public returns (SockAccount ret) {
        address addr = getAddress(
            aSockFunctionRegistry,
            anOwner,
            aSockOwner,
            salt
        );
        uint codeSize = addr.code.length;
        if (codeSize > 0) {
            return SockAccount(payable(addr));
        }
        ret = SockAccount(payable(new ERC1967Proxy{salt : bytes32(salt)}(
            address(accountImplementation),
            abi.encodeCall(
                SockAccount.initialize, (
                    aSockFunctionRegistry,
                    anOwner,
                    aSockOwner
                )
            )
        )));
        emit SockAccountCreated(address(ret));
    }

    /**
     * @notice Computes the counterfactual address of a SockAccount based on provided parameters.
     * @param aSockFunctionRegistry Reference to a SockFunctionRegistry contract.
     * @param anOwner Address of the owner of the SockAccount.
     * @param aSockOwner Address of the sockOwner of the SockAccount.
     * @param salt A salt value to generate a unique address for the new SockAccount.
     * @return The counterfactual address the SockAccount would have if created using the provided parameters.
     */
    function getAddress(
        ISockFunctionRegistry aSockFunctionRegistry,
        address anOwner,
        address aSockOwner,
        uint256 salt
    ) public view returns (address) {
        return Create2.computeAddress(bytes32(salt), keccak256(abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(
                address(accountImplementation),
                abi.encodeCall(
                    SockAccount.initialize, (
                        aSockFunctionRegistry,
                        anOwner,
                        aSockOwner
                    )
                )
            )
        )));
    }
}

