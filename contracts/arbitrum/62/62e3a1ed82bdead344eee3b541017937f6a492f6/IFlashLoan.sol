//  SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.10;

import {IERC20Metadata as IERC20} from "./extensions_IERC20Metadata.sol";
import {ICToken} from "./compound_ICToken.sol";

interface IVault {
  function flashLoan(
    IFlashLoanRecipient receiver,
    IERC20[] calldata tokens,
    uint256[] calldata amounts,
    bytes calldata userData
  ) external;
}

interface IFlashLoanRecipient {
  function receiveFlashLoan(
    IERC20[] memory tokens,
    uint256[] memory amounts,
    uint256[] memory feeAmounts,
    bytes memory userData
  ) external;
}

