// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.9;

import {ISynthereumTrustedForwarder} from "./ITrustedForwarder.sol";
import {Address} from "./Address.sol";
import {   MinimalForwarder } from "./MinimalForwarder.sol";

contract SynthereumTrustedForwarder is
  ISynthereumTrustedForwarder,
  MinimalForwarder
{
  /**
   * @notice Check if the execute function reverts or not
   */
  function safeExecute(ForwardRequest calldata req, bytes calldata signature)
    public
    payable
    override
    returns (bytes memory)
  {
    (bool success, bytes memory returndata) = execute(req, signature);
    return
      Address.verifyCallResult(
        success,
        returndata,
        'Error in the TrustedForwarder call'
      );
  }
}

