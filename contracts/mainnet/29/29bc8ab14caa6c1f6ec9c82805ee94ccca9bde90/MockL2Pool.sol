// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import {IInvestmentEarnings} from "./IInvestmentEarnings.sol";
import {L2Pool} from "./L2Pool.sol";

abstract contract MockL2Pool is L2Pool {

  constructor(
    IInvestmentEarnings investmentEarnings,
    address srcToken,
    address[] memory _owners,
    uint _required
  ) L2Pool(investmentEarnings, srcToken, _owners, _required) {}
}

