// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @dev Used to determine which calculation to use for the payment amount when taking a payment.
 *      STATIC: The payment amount is the input token without conversion.
 *      PRICED_IN_ERC20: The payment amount is priced in an ERC20 relative to the payment token.
 *      PRICED_IN_USD: The payment amount is priced in USD relative to the payment token.
 *      PRICED_IN_GAS_TOKEN: The payment amount is priced in the gas token relative to the payment token.
 */
enum PriceType {
    STATIC,
    PRICED_IN_ERC20,
    PRICED_IN_USD,
    PRICED_IN_GAS_TOKEN
}

enum PaymentType {
    ETH_IN_USD,
    MAGIC_IN_USD,
    ARB_IN_USD
}

interface IPayments {
    /**
     * @dev Emitted when a payment is made
     * @param payor The address of the sender of the payment
     * @param token The address of the token that was paid. If address(0), then it was gas token
     * @param amount The amount of the token that was paid
     * @param paymentsReceiver The address of the contract that received the payment. Supports IPaymentsReceiver
     */
    event PaymentSent(address payor, address token, uint256 amount, address paymentsReceiver);

    /**
     * @dev Make a payment in ERC20 to the recipient
     * @param _recipient The address of the recipient of the payment
     * @param _paymentERC20 The address of the ERC20 to take
     * @param _price The amount of the ERC20 to take
     */
    function makeStaticERC20Payment(address _recipient, address _paymentERC20, uint256 _price) external;

    /**
     * @dev Make a payment in gas token to the recipient.
     *      All this does is verify that the price matches the tx value
     * @param _recipient The address of the recipient of the payment
     * @param _price The amount of the gas token to take
     */
    function makeStaticGasTokenPayment(address _recipient, uint256 _price) external payable;

    /**
     * @dev Make a payment in ERC20 to the recipient priced in another token (Gas Token/USD/other ERC20)
     * @param _recipient The address of the payor to take the payment from
     * @param _paymentERC20 The address of the ERC20 to take
     * @param _paymentAmountInPricedToken The desired payment amount, priced in another token, depending on what `priceType` is
     * @param _priceType The type of currency that the payment amount is priced in
     * @param _pricedERC20 The address of the ERC20 that the payment amount is priced in. Only used if `_priceType` is PRICED_IN_ERC20
     */
    function makeERC20PaymentByPriceType(
        address _recipient,
        address _paymentERC20,
        uint256 _paymentAmountInPricedToken,
        PriceType _priceType,
        address _pricedERC20
    ) external;

    /**
     * @dev Take payment in gas tokens (ETH, MATIC, etc.) priced in another token (USD/ERC20)
     * @param _recipient The address to send the payment to
     * @param _paymentAmountInPricedToken The desired payment amount, priced in another token, depending on what `_priceType` is
     * @param _priceType The type of currency that the payment amount is priced in
     * @param _pricedERC20 The address of the ERC20 that the payment amount is priced in. Only used if `_priceType` is PRICED_IN_ERC20
     */
    function makeGasTokenPaymentByPriceType(
        address _recipient,
        uint256 _paymentAmountInPricedToken,
        PriceType _priceType,
        address _pricedERC20
    ) external payable;

    /**
     * @dev Admin-only function that initializes the ERC20 info for a given ERC20.
     *      Currently there are no price feeds for ERC20s, so those parameters are a placeholder
     * @param _paymentERC20 The ERC20 address
     * @param _decimals The number of decimals of this coin.
     * @param _pricedInGasTokenAggregator The aggregator for the gas coin (ETH, MATIC, etc.)
     * @param _usdAggregator The aggregator for USD
     * @param _pricedERC20s The ERC20s that have supported price feeds for the given ERC20
     * @param _priceFeeds The price feeds for the priced ERC20s
     */
    function initializeERC20(
        address _paymentERC20,
        uint8 _decimals,
        address _pricedInGasTokenAggregator,
        address _usdAggregator,
        address[] calldata _pricedERC20s,
        address[] calldata _priceFeeds
    ) external;

    /**
     * @dev Admin-only function that sets the price feed for a given ERC20.
     *      Currently there are no price feeds for ERC20s, so this is a placeholder
     * @param _paymentERC20 The ERC20 to set the price feed for
     * @param _pricedERC20 The ERC20 that is associated to the given price feed and `_paymentERC20`
     * @param _priceFeed The address of the price feed
     */
    function setERC20PriceFeedForERC20(address _paymentERC20, address _pricedERC20, address _priceFeed) external;

    /**
     * @dev Admin-only function that sets the price feed for the gas token for the given ERC20.
     * @param _pricedERC20 The ERC20 that is associated to the given price feed and `_paymentERC20`
     * @param _priceFeed The address of the price feed
     */
    function setERC20PriceFeedForGasToken(address _pricedERC20, address _priceFeed) external;

    /**
     * @param _paymentToken The token to convert from. If address(0), then the input is in gas tokens
     * @param _priceType The type of currency that the payment amount is priced in
     * @param _pricedERC20 The address of the ERC20 that the payment amount is priced in. Only used if `_priceType` is PRICED_IN_ERC20
     * @return supported_ Whether or not a price feed exists for the given payment token and price type
     */
    function isValidPriceType(
        address _paymentToken,
        PriceType _priceType,
        address _pricedERC20
    ) external view returns (bool supported_);

    /**
     * @dev Calculates the price of the input token relative to the output token
     * @param _paymentToken The token to convert from. If address(0), then the input is in gas tokens
     * @param _paymentAmountInPricedToken The desired payment amount, priced in either the `_pricedERC20`, gas token, or USD depending on `_priceType`
     *      used to calculate the output amount
     * @param _priceType The type of conversion to perform
     * @param _pricedERC20 The token to convert to. If address(0), then the output is in gas tokens or USD, depending on `_priceType`
     */
    function calculatePaymentAmountByPriceType(
        address _paymentToken,
        uint256 _paymentAmountInPricedToken,
        PriceType _priceType,
        address _pricedERC20
    ) external view returns (uint256 paymentAmount_);

    /**
     * @return magicAddress_ The address of the $MAGIC contract
     */
    function getMagicAddress() external view returns (address magicAddress_);
}

