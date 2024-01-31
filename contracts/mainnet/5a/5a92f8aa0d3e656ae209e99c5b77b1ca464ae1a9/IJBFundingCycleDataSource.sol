// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "./IERC165.sol";
import "./JBPayParamsData.sol";
import "./JBRedeemParamsData.sol";
import "./IJBFundingCycleStore.sol";
import "./IJBPayDelegate.sol";
import "./IJBRedemptionDelegate.sol";

interface IJBFundingCycleDataSource is IERC165 {
  function payParams(JBPayParamsData calldata _data)
    external
    returns (
      uint256 weight,
      string memory memo,
      IJBPayDelegate delegate
    );

  function redeemParams(JBRedeemParamsData calldata _data)
    external
    returns (
      uint256 reclaimAmount,
      string memory memo,
      IJBRedemptionDelegate delegate
    );
}

