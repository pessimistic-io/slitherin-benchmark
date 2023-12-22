// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.17;

import "./IController.sol";
import "./ITradePair.sol";
import "./UnlimitedOwnable.sol";

contract Controller is IController, UnlimitedOwnable {
    /* ========== STATE VARIABLES ========== */

    /// @notice Is trade pair registered
    mapping(address => bool) public isTradePair;

    /// @notice Is liquidity pool registered
    mapping(address => bool) public isLiquidityPool;

    /// @notice Is liquidity pool adapter registered
    mapping(address => bool) public isLiquidityPoolAdapter;

    /// @notice Is price fee adapter registered
    mapping(address => bool) public isPriceFeed;

    /// @notice Is price fee adapter registered
    mapping(address => bool) public isUpdatable;

    /// @notice Is signer registered
    mapping(address => bool) public isSigner;

    /// @notice Is order executor registered
    mapping(address => bool) public isOrderExecutor;

    /// @notice Returns order reward for collateral token
    /// @dev Order reward is payed to executor of the order book (mainly Unlimited order book backend)
    /// It is payed by a maker and added on top of the margin
    /// Unlimited is collateral token agnostic, so the order reward can be different for different collaterals
    mapping(address => uint256) public orderRewardOfCollateral;

    /**
     * @notice Initializes immutable variables.
     * @param unlimitedOwner_ UnlimitedOwner contract.
     */
    constructor(IUnlimitedOwner unlimitedOwner_) UnlimitedOwnable(unlimitedOwner_) {}

    /* ========== EXTERNAL FUNCTIONS ========== */

    /**
     * @notice Adds the trade pair to the registry
     * @dev
     * Requirements:
     *
     * - Caller must be owner.
     * - The contract must not be paused.
     * - Trade pair must be valid.
     *
     * @param tradePair_ Trade pair address.
     */
    function addTradePair(address tradePair_)
        external
        onlyOwner
        onlyNonZeroAddress(tradePair_)
        onlyValidTradePair(tradePair_)
    {
        isTradePair[tradePair_] = true;

        emit TradePairAdded(tradePair_);
    }

    /**
     * @notice Adds the liquidity pool to the registry
     * @dev
     * Requirements:
     *
     * - Caller must be owner.
     * - The contract must not be paused.
     *
     * @param liquidityPool_ Liquidity pool address.
     */
    function addLiquidityPool(address liquidityPool_) external onlyOwner onlyNonZeroAddress(liquidityPool_) {
        isLiquidityPool[liquidityPool_] = true;

        emit LiquidityPoolAdded(liquidityPool_);
    }

    /**
     * @notice Adds the liquidity pool adapter to the registry
     * @dev
     * Requirements:
     *
     * - Caller must be owner.
     * - The contract must not be paused.
     *
     * @param liquidityPoolAdapter_ Liquidity pool adapter address.
     */
    function addLiquidityPoolAdapter(address liquidityPoolAdapter_)
        external
        onlyOwner
        onlyNonZeroAddress(liquidityPoolAdapter_)
    {
        isLiquidityPoolAdapter[liquidityPoolAdapter_] = true;

        emit LiquidityPoolAdapterAdded(liquidityPoolAdapter_);
    }

    /**
     * @notice Adds the price feed to the registry
     * @dev
     * Requirements:
     *
     * - Caller must be owner.
     * - The contract must not be paused.
     *
     * @param priceFeed_ Price feed address.
     */
    function addPriceFeed(address priceFeed_) external onlyOwner onlyNonZeroAddress(priceFeed_) {
        isPriceFeed[priceFeed_] = true;

        emit PriceFeedAdded(priceFeed_);
    }

    /**
     * @notice Adds an updatable contract to the registry
     * @param contractAddress_ The address of the updatable contract
     */
    function addUpdatable(address contractAddress_) external onlyOwner onlyNonZeroAddress(contractAddress_) {
        isUpdatable[contractAddress_] = true;

        emit UpdatableAdded(contractAddress_);
    }

    /**
     * @notice Removes the trade pair from the registry
     * @dev
     * Requirements:
     *
     * - Caller must be owner.
     * - The contract must not be paused.
     * - Trade pair must be already added.
     *
     * @param tradePair_ Trade pair address.
     */
    function removeTradePair(address tradePair_) external onlyOwner onlyActiveTradePair(tradePair_) {
        isTradePair[tradePair_] = false;

        emit TradePairRemoved(tradePair_);
    }

    /**
     * @notice Removes the liquidity pool from the registry
     * @dev
     * Requirements:
     *
     * - Caller must be owner.
     * - The contract must not be paused.
     * - Liquidity pool must be already added.
     *
     * @param liquidityPool_ Liquidity pool address.
     */
    function removeLiquidityPool(address liquidityPool_) external onlyOwner onlyActiveLiquidityPool(liquidityPool_) {
        isLiquidityPool[liquidityPool_] = false;

        emit LiquidityPoolRemoved(liquidityPool_);
    }

    /**
     * @notice Removes the liquidity pool adapter from the registry
     * @dev
     * Requirements:
     *
     * - Caller must be owner.
     * - The contract must not be paused.
     * - Liquidity pool adapter must be already added.
     *
     * @param liquidityPoolAdapter_ Liquidity pool adapter address.
     */
    function removeLiquidityPoolAdapter(address liquidityPoolAdapter_)
        external
        onlyOwner
        onlyActiveLiquidityPoolAdapter(liquidityPoolAdapter_)
    {
        isLiquidityPoolAdapter[liquidityPoolAdapter_] = false;

        emit LiquidityPoolAdapterRemoved(liquidityPoolAdapter_);
    }

    /**
     * @notice Removes the price feed from the registry
     * @dev
     * Requirements:
     *
     * - Caller must be owner.
     * - The contract must not be paused.
     * - Price feed must be already added.
     *
     * @param priceFeed_ Price feed address.
     */
    function removePriceFeed(address priceFeed_) external onlyOwner onlyActivePriceFeed(priceFeed_) {
        isPriceFeed[priceFeed_] = false;

        emit PriceFeedRemoved(priceFeed_);
    }

    /**
     * @notice Removes an updatable contract from the registry
     * @param contractAddress_ The address of the updatable contract
     */
    function removeUpdatable(address contractAddress_) external onlyOwner onlyNonZeroAddress(contractAddress_) {
        isUpdatable[contractAddress_] = false;

        emit UpdatableRemoved(contractAddress_);
    }

    /**
     * @notice Sets order reward for collateral
     * @param collateral_ address of the collateral token
     * @param orderReward_ order reward (in decimals of collateral token)
     */
    function setOrderRewardOfCollateral(address collateral_, uint256 orderReward_)
        external
        onlyOwner
        onlyNonZeroAddress(collateral_)
    {
        orderRewardOfCollateral[collateral_] = orderReward_;

        emit SetOrderRewardOfCollateral(collateral_, orderReward_);
    }

    /**
     * @notice Reverts if trade pair inactive
     * @param tradePair_ trade pair address
     */
    function checkTradePairActive(address tradePair_) external view {
        _onlyActiveTradePair(tradePair_);
    }

    /**
     * @notice Function to add a valid signer
     * @param signer_ address of the signer
     */
    function addSigner(address signer_) external onlyOwner {
        isSigner[signer_] = true;
        emit SignerAdded(signer_);
    }

    /**
     * @notice Function to remove a valid signer
     * @param signer_ address of the signer
     */
    function removeSigner(address signer_) external onlyOwner {
        isSigner[signer_] = false;
        emit SignerRemoved(signer_);
    }

    /**
     * @notice Function to add a valid order executor
     * @param orderExecutor_ address of the order executor
     */
    function addOrderExecutor(address orderExecutor_) external onlyOwner {
        isOrderExecutor[orderExecutor_] = true;
        emit OrderExecutorAdded(orderExecutor_);
    }

    /**
     * @notice Function to remove a valid order executor
     * @param orderExecutor_ address of the order executor
     */
    function removeOrderExecutor(address orderExecutor_) external onlyOwner {
        isOrderExecutor[orderExecutor_] = false;
        emit OrderExecutorRemoved(orderExecutor_);
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    /**
     * @dev Reverts when TradePair is not active
     */
    function _onlyActiveTradePair(address tradePair_) private view {
        require(isTradePair[tradePair_], "Controller::_onlyActiveTradePair: invalid trade pair.");
    }

    /**
     * @dev Reverts when LiquidityPool is not valid
     */
    function _onlyActiveLiquidityPool(address liquidityPool_) private view {
        require(isLiquidityPool[liquidityPool_], "Controller::_onlyActiveLiquidityPool: invalid liquidity pool.");
    }

    /**
     * @dev Reverts when LiquidityPoolAdapter is not valid
     */
    function _onlyActiveLiquidityPoolAdapter(address liquidityPoolAdapter_) private view {
        require(
            isLiquidityPoolAdapter[liquidityPoolAdapter_],
            "Controller::_onlyActiveLiquidityPoolAdapter: invalid liquidity pool adapter."
        );
    }

    /**
     * @dev Reverts when PriceFeed is not valid
     */
    function _onlyActivePriceFeed(address priceFeed_) private view {
        require(isPriceFeed[priceFeed_], "Controller::_onlyActivePriceFeed: invalid price feed.");
    }

    /**
     * @dev Reverts when the TradePair is not active or has an invalid liquidity pool
     */
    function _onlyValidTradePair(ITradePair tradePair_) private view {
        _onlyActiveLiquidityPoolAdapter(address(tradePair_.liquidityPoolAdapter()));
        _onlyActivePriceFeed(address(tradePair_.priceFeedAdapter()));
    }

    /**
     * @dev Reverts when address is zero address
     */
    function _onlyNonZeroAddress(address address_) private pure {
        require(address_ != address(0), "Controller::_onlyNonZeroAddress: Address is 0");
    }

    /* ========== MODIFIERS ========== */

    /**
     * @notice Reverts if trade pair not in the registry
     */
    modifier onlyActiveTradePair(address tradePair_) {
        _onlyActiveTradePair(tradePair_);
        _;
    }

    /**
     * @notice Reverts if liquidity pool not in the registry
     */
    modifier onlyActiveLiquidityPool(address liquidityPool_) {
        _onlyActiveLiquidityPool(liquidityPool_);
        _;
    }

    /**
     * @notice Reverts if liquidity pool adapter not in the registry
     */
    modifier onlyActiveLiquidityPoolAdapter(address liquidityPoolAdapter_) {
        _onlyActiveLiquidityPoolAdapter(liquidityPoolAdapter_);
        _;
    }

    /**
     * @notice Reverts if price feed not in the registry
     */
    modifier onlyActivePriceFeed(address priceFeed_) {
        _onlyActivePriceFeed(priceFeed_);
        _;
    }

    /**
     * @notice Reverts if trade pair invalid - i.e. its price feed or liquidity pool adapter are not registered
     * in the system.
     */
    modifier onlyValidTradePair(address tradePair_) {
        _onlyValidTradePair(ITradePair(tradePair_));
        _;
    }

    /**
     * @notice Reverts if give address is 0
     */
    modifier onlyNonZeroAddress(address address_) {
        _onlyNonZeroAddress(address_);
        _;
    }
}

