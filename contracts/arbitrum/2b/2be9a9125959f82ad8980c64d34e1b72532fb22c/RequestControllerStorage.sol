// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "./Selector.sol";
import "./AdminControl.sol";
import "./IMiddleLayer.sol";

abstract contract RequestControllerStorage is AdminControl, Selector {

    /**
    * @notice Master ChainId
    */
    // slither-disable-next-line unused-state
    uint256 public masterCID;

    /**
    * @notice Indicates whether the market is accepting new borrows
    */
    mapping(address /* LoanMarketAsset */ => bool) public isdeprecated;

    /**
     * @notice Indicates whether the loan market is frozen
     */
    mapping(address /* LoanMarketAsset */ => bool) public isLoanMarketFrozen;

    /**
     * @notice Indicates whether the pToken market is frozen
     */
    mapping(address /* PToken */ => bool) public isPTokenFrozen;

    /**
    * @notice MiddleLayer Interface
    */
    // slither-disable-next-line unused-state
    IMiddleLayer internal middleLayer;

    /**
     * @notice EIP-20 token decimals for this token
     */
    uint8 public constant EXCHANGE_RATE_DECIMALS = 18;
}

