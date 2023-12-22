// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "./Selector.sol";
import "./AdminControl.sol";
import "./IMiddleLayer.sol";

abstract contract PTokenStorage is Selector, AdminControl {

    /**
     * @notice EIP-20 token for this PToken
     */
    address public underlying;

    /**
     * @notice EIP-20 token decimals for this token
     */
    uint8 public decimals;

    /**
     * @notice EIP-20 token decimals for this token
     */
    uint8 public constant EXCHANGE_RATE_DECIMALS = 18;

    /**
     * @notice Master ChainId
     */
    // slither-disable-next-line unused-state
    uint256 public masterCID;

    /**
    * @notice Indicates whether the market is accepting deposits
    */
    bool public isdeprecated;

    /**
     * @notice Indicates whether the market is frozen
     */
    bool public isFrozen;

    /**
     * @notice The decimals of the underlying asset of this pToken's underlying, e.g. ETH of CETH of PCETH.
     */
    uint8 public underlyingDecimalsOfUnderlying;

    /**
     * @notice The current exchange rate between pToken deposits and underlying
     */
    uint256 public currentExchangeRate;

    /**
     * @notice MiddleLayer Interface
     */
    // slither-disable-next-line unused-state
    IMiddleLayer internal middleLayer;

    address internal requestController;
}

