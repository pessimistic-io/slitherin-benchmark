// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import "./Create2.sol";
import "./ERC1967Proxy.sol";

import "./SecAccount.sol";
import "./ISec.sol";

/**
 * A sample factory contract for SimpleAccount
 * A UserOperations "initCode" holds the address of the factory, and a method call (to createAccount, in this sample factory).
 * The factory's createAccount returns the target account address even if it is already installed.
 * This way, the entryPoint.getSenderAddress() can be called either before or after the account is created.
 */
contract SecAccountFactory {
    SecAccount public immutable accountImplementation;

    constructor(IEntryPoint _entryPoint, ISec _sec) {
        accountImplementation = new SecAccount(_entryPoint, _sec);
    }

    /**
     * create an account, and return its address.
     * returns the address even if the account is already deployed.
     * Note that during UserOperation execution, this method is called only if the account is not deployed.
     * This method returns an existing account address so that entryPoint.getSenderAddress() would work even after account creation
     */
    function createAccount(address owner, uint256 salt)
        public
        returns (SecAccount ret)
    {
        address addr = getAddress(owner, salt);
        uint256 codeSize = addr.code.length;
        if (codeSize > 0) {
            return SecAccount(payable(addr));
        }
        ret = SecAccount(
            payable(
                new ERC1967Proxy{salt: bytes32(salt)}(
                    address(accountImplementation),
                    abi.encodeCall(SecAccount.initialize, (owner))
                )
            )
        );
    }

    /**
     * calculate the counterfactual address of this account as it would be returned by createAccount()
     */
    function getAddress(address owner, uint256 salt)
        public
        view
        returns (address)
    {
        return
            Create2.computeAddress(
                bytes32(salt),
                keccak256(
                    abi.encodePacked(
                        type(ERC1967Proxy).creationCode,
                        abi.encode(
                            address(accountImplementation),
                            abi.encodeCall(SecAccount.initialize, (owner))
                        )
                    )
                )
            );
    }

    function getCode() public pure returns  (bytes memory){
        return type(ERC1967Proxy).creationCode;
    }
    function getEncodeCall(address owner) public pure returns  (bytes memory){
        return abi.encodeCall(SecAccount.initialize, (owner));
    }
}

