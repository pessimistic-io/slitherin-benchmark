// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import "./Create2.sol";
import "./ERC1967Proxy.sol";

import "./Account.sol";

import "./ISingleton.sol";

/**
 * A sample factory contract for Account
 * A UserOperations "initCode" holds the address of the factory, and a method call (to createAccount, in this sample factory).
 * The factory's createAccount returns the target account address even if it is already installed.
 * This way, the entryPoint.getSenderAddress() can be called either before or after the account is created.
 */
contract AccountFactory {
  Account public immutable accountImplementation;

  ISingleton public immutable singleton;
  address public immutable relayer;

  constructor(IEntryPoint _entryPoint, ISingleton _singleton, address _relayer) {
    singleton = _singleton;
    relayer = _relayer;
    accountImplementation = new Account(_entryPoint, _singleton);
  }

  /**
   * create an account, and return its address.
   * returns the address even if the account is already deployed.
   * Note that during UserOperation execution, this method is called only if the account is not deployed.
   * This method returns an existing account address so that entryPoint.getSenderAddress() would work even after account creation
   */
  function createAccount(address owner, uint256 salt) public returns (Account ret) {
    address addr = getAddress(owner, salt);
    uint codeSize = addr.code.length;
    if (codeSize > 0) {
      return Account(payable(addr));
    }
    ret = Account(
      payable(
        new ERC1967Proxy{ salt: bytes32(salt) }(
          address(accountImplementation),
          abi.encodeCall(Account.initialize, (owner, relayer))
        )
      )
    );
  }

  /**
   * calculate the counterfactual address of this account as it would be returned by createAccount()
   */
  function getAddress(address owner, uint256 salt) public view returns (address) {
    return
      Create2.computeAddress(
        bytes32(salt),
        keccak256(
          abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(address(accountImplementation), abi.encodeCall(Account.initialize, (owner, relayer)))
          )
        )
      );
  }
}

