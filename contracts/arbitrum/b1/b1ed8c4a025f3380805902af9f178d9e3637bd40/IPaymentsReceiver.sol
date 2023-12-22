// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {PriceType} from "./IPayments.sol";

interface IPaymentsReceiver {
    /**
     * @dev Emitted when a payment is made
     * @param payor The address of the sender of the payment
     * @param paymentERC20 The address of the token that was paid. If address(0), then it was gas token
     * @param paymentAmount The amount of the token that was paid
     * @param paymentAmountInPricedToken The payment amount of the given priced token. Used to have dynamic payments based on the value relative to another token
     * @param priceType The type of payment that was made. This can be static payment or priced in another currency
     * @param pricedERC20 The address of the ERC20 token that was used to price the payment. Only used if `_priceType` is PRICED_IN_ERC20
     */
    event PaymentReceived(
        address payor,
        address paymentERC20,
        uint256 paymentAmount,
        uint256 paymentAmountInPricedToken,
        PriceType priceType,
        address pricedERC20
    );

    /**
     * @dev Accepts a payment in ERC20 tokens
     * @param _payor The address of the payor for this payment
     * @param _paymentERC20 The address of the ERC20 token that was paid
     * @param _paymentAmount The amount of the ERC20 token that was paid
     * @param _paymentAmountInPricedToken The amount of the ERC20 token that was paid in the given priced token
     *      For example, if the payment is the amount of MAGIC that equals $10 USD,
     *      then this value would be 10 * 10**8 (the number of decimals for USD)
     * @param _priceType The type of payment that was made. This can be static payment or priced in another currency
     * @param _pricedERC20 The address of the ERC20 token that was used to price the payment. Only used if `_priceType` is `PriceType.PRICED_IN_ERC20`
     */
    function acceptERC20(
        address _payor,
        address _paymentERC20,
        uint256 _paymentAmount,
        uint256 _paymentAmountInPricedToken,
        PriceType _priceType,
        address _pricedERC20
    ) external;

    /**
     * @dev Accepts a payment in gas tokens
     * @param _payor The address of the payor for this payment
     * @param _paymentAmount The amount of the gas token that was paid
     * @param _paymentAmountInPricedToken The amount of the gas token that was paid in the given priced token
     *      For example, if the payment is the amount of ETH that equals $10 USD,
     *      then this value would be 10 * 10**8 (the number of decimals for USD)
     * @param _priceType The type of payment that was made. This can be static payment or priced in another currency
     * @param _pricedERC20 The address of the ERC20 token that was used to price the payment. Only used if `_priceType` is `PriceType.PRICED_IN_ERC20`
     */
    function acceptGasToken(
        address _payor,
        uint256 _paymentAmount,
        uint256 _paymentAmountInPricedToken,
        PriceType _priceType,
        address _pricedERC20
    ) external payable;
}

