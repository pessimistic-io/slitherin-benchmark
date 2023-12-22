// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { AttestationPayload } from "./Structs.sol";
import { Ownable } from "./Ownable.sol";
import { AbstractPortal } from "./AbstractPortal.sol";

/**
 * @title Clique Portal
 * @author Clique
 * @notice This contract is a Portal used by Clique to issue attestations
 */
contract CliquePortal is AbstractPortal, Ownable {
  /// @dev Error thrown when the withdraw fails
  error WithdrawFail();

  constructor(address[] memory _modules, address _router) AbstractPortal(_modules, _router) {}

  function withdraw(address payable to, uint256 amount) external override onlyOwner {
    (bool s, ) = to.call{ value: amount }("");
    if (!s) revert WithdrawFail();
  }
}

