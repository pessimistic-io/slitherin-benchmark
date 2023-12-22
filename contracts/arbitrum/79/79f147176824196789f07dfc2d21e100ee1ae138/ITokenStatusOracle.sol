// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.5.0;

import "./IBoolOracle.sol";

interface ITokenStatusOracle is IBoolOracle {
  function verifyTokenStatus(
    address contractAddr,
    uint tokenId,
    bool isFlagged,
    uint lastTransferTime,
    uint timestamp,
    bytes memory signature
  ) external view; 
}

