// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {IERC20Upgradeable} from "./ERC20_IERC20Upgradeable.sol";
import "./MathUpgradeable.sol";
import "./IPlatformAdapter.sol";
import "./IAdapter.sol";
import "./IGmxAdapter.sol";
import "./IGmxOrderBook.sol";
import "./IGmxReader.sol";
import "./IGmxRouter.sol";
import "./IGmxVault.sol";
import "./ITraderWallet.sol";
import {SafeERC20Upgradeable} from "./SafeERC20Upgradeable.sol";


// import "hardhat/console.sol";

library GMXAdapter {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using MathUpgradeable for uint256;

    address internal constant gmxRouter =
        0xaBBc5F99639c9B6bCb58544ddf04EFA6802F4064;
    address internal constant gmxPositionRouter =
        0xb87a436B93fFE9D75c5cFA7bAcFff96430b09868;
    IGmxVault internal constant gmxVault =
        IGmxVault(0x489ee077994B6658eAfA855C308275EAd8097C4A);
    address internal constant gmxOrderBook =
        0x09f77E8A13De9a35a7231028187e9fD5DB8a2ACB;
    address internal constant gmxOrderBookReader =
        0xa27C20A7CF0e1C68C0460706bB674f98F362Bc21;
    address internal constant gmxReader =
        0x22199a49A999c351eF7927602CFB187ec3cae489;

    /// @notice The ratio denominator between traderWallet and usersVault
    uint256 private constant ratioDenominator = 1e18;

    /// @notice The slippage allowance for swap in the position
    uint256 public constant slippage = 1e17; // 10%    

    struct IncreaseOrderLocalVars {
        address[] path;
        uint256 amountIn;
        address indexToken;
        uint256 minOut;
        uint256 sizeDelta;
        bool isLong;
        uint256 triggerPrice;
        bool triggerAboveThreshold;
    }

    event CreateIncreasePosition(address sender, bytes32 requestKey);
    event CreateDecreasePosition(address sender, bytes32 requestKey);

    error AddressZero();
    error InsufficientEtherBalance();
    error InvalidOperationId();
    error CreateSwapOrderFail();
    error CreateIncreasePositionFail(string);
    error CreateDecreasePositionFail(string);
    error CreateIncreasePositionOrderFail(string);
    error CreateDecreasePositionOrderFail(string);
    error NotSupportedTokens(address, address);
    error TooManyOrders();

    /// @notice Gives approve to operate with gmxPositionRouter
    /// @dev Needs to be called from wallet and vault in initialization
    function __initApproveGmxPlugin() external {
        IGmxRouter(gmxRouter).approvePlugin(gmxPositionRouter);
        IGmxRouter(gmxRouter).approvePlugin(gmxOrderBook);
    }

    /// @notice Executes operation with external protocol
    /// @param ratio Scaling ratio to
    /// @param traderOperation Encoded operation data
    /// @return bool 'true' if the operation completed successfully
    function executeOperation(
        bool isTraderWallet,
        address traderWallet,
        address usersVault,
        uint256 ratio,
        IAdapter.AdapterOperation memory traderOperation
    ) external returns (bool, uint256) {
        if (uint256(traderOperation.operationId) == 0) {
            return
                _increasePosition(
                    isTraderWallet,
                    traderWallet,
                    usersVault,
                    ratio,
                    traderOperation.data
                );
        } else if (traderOperation.operationId == 1) {
            return
                _decreasePosition(
                    isTraderWallet,
                    traderWallet,
                    usersVault,
                    ratio,
                    traderOperation.data
                );
        } else if (traderOperation.operationId == 2) {
            return
                _createIncreaseOrder(
                    isTraderWallet,
                    traderWallet,
                    usersVault,
                    ratio,
                    traderOperation.data
                );
        } else if (traderOperation.operationId == 3) {
            return
                _updateIncreaseOrder(
                    isTraderWallet,
                    traderWallet,
                    usersVault,
                    ratio,
                    traderOperation.data
                );
        } else if (traderOperation.operationId == 4) {
            return _cancelIncreaseOrder(isTraderWallet, traderOperation.data);
        } else if (traderOperation.operationId == 5) {
            return
                _createDecreaseOrder(
                    isTraderWallet,
                    traderWallet,
                    usersVault,
                    ratio,
                    traderOperation.data
                );
        } else if (traderOperation.operationId == 6) {
            return
                _updateDecreaseOrder(
                    isTraderWallet,
                    traderWallet,
                    usersVault,
                    ratio,
                    traderOperation.data
                );
        } else if (traderOperation.operationId == 7) {
            return _cancelDecreaseOrder(isTraderWallet, traderOperation.data);
        }
        revert InvalidOperationId();
    }

    /*
    @notice Opens new or increases the size of an existing position
    @param tradeData must contain parameters:
        path:       [collateralToken] or [tokenIn, collateralToken] if a swap is needed
        indexToken: the address of the token to long or short
        amountIn:   the amount of tokenIn to deposit as collateral
        minOut:     the min amount of collateralToken to swap for (can be zero if no swap is required)
        sizeDelta:  the USD value of the change in position size  (scaled 1e30)
        isLong:     whether to long or short position
        priceAllowedSlippage: allowed slippage for acceptable price; default 30(0.3%); range is [0, 500(5%)]

    Additional params for increasing position
        executionFee:   can be set to PositionRouter.minExecutionFee
        referralCode:   referral code for affiliate rewards and rebates
        callbackTarget: an optional callback contract (note: has gas limit)
        acceptablePrice: the USD value of the max (for longs) or min (for shorts) index price acceptable when executing
    @return bool - Returns 'true' if position was created
    @return ratio_ - Value for scaling amounts from TraderWallet to UsersVault
    */
    function _increasePosition(
        bool isTraderWallet,
        address traderWallet,
        address usersVault,
        uint256 ratio,
        bytes memory tradeData
    ) internal returns (bool, uint256 ratio_) {
        (
            address[] memory path,
            address indexToken,
            uint256 amountIn,
            uint256 minOut,
            uint256 sizeDelta,
            bool isLong,
            uint256 priceAllowedSlippage
        ) = abi.decode(
                tradeData,
                (address[], address, uint256, uint256, uint256, bool, uint256)
            );

        if (isTraderWallet) {
            {
                // only one check is enough
                address collateralToken = path[path.length - 1];
                if (
                    !_validateTradeTokens(
                        traderWallet,
                        collateralToken,
                        indexToken,
                        isLong
                    )
                ) {
                    revert NotSupportedTokens(collateralToken, indexToken);
                }
            }
            // calculate ratio for UserVault based on balances of tokenIn (path[0])
            uint256 traderBalance = IERC20Upgradeable(path[0]).balanceOf(traderWallet);
            uint256 vaultBalance = IERC20Upgradeable(path[0]).balanceOf(usersVault);
            ratio_ = vaultBalance.mulDiv(
                ratioDenominator,
                traderBalance,
                MathUpgradeable.Rounding.Down
            );
        } else {
            // scaling for Vault execution
            amountIn = (amountIn * ratio) / ratioDenominator;
            uint256 amountInAvailable = IERC20Upgradeable(path[0]).balanceOf(
                address(this)
            );
            if (amountInAvailable < amountIn) amountIn = amountInAvailable;
            sizeDelta = (sizeDelta * ratio) / ratioDenominator;
            minOut = (minOut * ratio) / (ratioDenominator + slippage); // decreased due to price impact
        }

        _checkUpdateAllowance(path[0], address(gmxRouter), amountIn);
        uint256 executionFee = IGmxPositionRouter(gmxPositionRouter)
            .minExecutionFee();
        if (address(this).balance < executionFee)
            revert InsufficientEtherBalance();

        uint256 acceptablePrice;
        {
            uint256 refPrice;
            uint256 priceBasisPoints;
            uint256 priceBasisPointsDivisor = 10000;
            if (isLong) {
                refPrice = gmxVault.getMaxPrice(indexToken);
                priceBasisPoints = priceBasisPointsDivisor + priceAllowedSlippage;
            } else {
                refPrice = gmxVault.getMinPrice(indexToken);
                priceBasisPoints = priceBasisPointsDivisor - priceAllowedSlippage;
            }
            acceptablePrice = (refPrice * priceBasisPoints) / priceBasisPointsDivisor;
        }

        (bool success, bytes memory data) = gmxPositionRouter.call{
            value: executionFee
        }(
            abi.encodeWithSelector(
                IGmxPositionRouter.createIncreasePosition.selector,
                path,
                indexToken,
                amountIn,
                minOut,
                sizeDelta,
                isLong,
                acceptablePrice,
                executionFee,
                0, // referralCode
                address(0) // callbackTarget
            )
        );

        if (!success) {
            revert CreateIncreasePositionFail(_getRevertMsg(data));
        }
        emit CreateIncreasePosition(address(this), bytes32(data));
        return (true, ratio_);
    }

    /*
    @notice Closes or decreases an existing position
    @param tradeData must contain parameters:
        path:            [collateralToken] or [collateralToken, tokenOut] if a swap is needed
        indexToken:      the address of the token that was longed (or shorted)
        collateralDelta: the amount of collateral in USD value to withdraw (doesn't matter when position is completely closing)
        sizeDelta:       the USD value of the change in position size (scaled to 1e30)
        isLong:          whether the position is a long or short
        minOut:          the min output token amount (can be zero if no swap is required)
        priceAllowedSlippage: allowed slippage for acceptable price; default 30(0.3%); range is [0, 500(5%)]

    Additional params for increasing position
        receiver:       the address to receive the withdrawn tokens
        acceptablePrice: the USD value of the max (for longs) or min (for shorts) index price acceptable when executing
        executionFee:   can be set to PositionRouter.minExecutionFee
        withdrawETH:    only applicable if WETH will be withdrawn, the WETH will be unwrapped to ETH if this is set to true
        callbackTarget: an optional callback contract (note: has gas limit)
    @return bool - Returns 'true' if position was created
    @return ratio_ - Value for scaling amounts from TraderWallet to UsersVault
    */
    function _decreasePosition(
        bool isTraderWallet,
        address traderWallet,
        address usersVault,
        uint256 ratio,
        bytes memory tradeData
    ) internal returns (bool, uint256 ratio_) {
        (
            address[] memory path,
            address indexToken,
            uint256 collateralDelta,
            uint256 sizeDelta,
            bool isLong,
            uint256 minOut,
            uint256 priceAllowedSlippage
        ) = abi.decode(
                tradeData,
                (address[], address, uint256, uint256, bool, uint256, uint256)
            );
        uint256 executionFee = IGmxPositionRouter(gmxPositionRouter)
            .minExecutionFee();
        if (address(this).balance < executionFee)
            revert InsufficientEtherBalance();

        if (isTraderWallet) {
            // calculate ratio for UserVault based on size of opened position
            uint256 traderSize = _getPosition(
                traderWallet,
                path[0],
                indexToken,
                isLong
            )[0];
            uint256 vaultSize = _getPosition(
                usersVault,
                path[0],
                indexToken,
                isLong
            )[0];
            ratio_ = vaultSize.mulDiv(
                ratioDenominator,
                traderSize,
                MathUpgradeable.Rounding.Up
            );
        } else {
            // scaling for Vault
            uint256[] memory vaultPosition = _getPosition(
                usersVault,
                path[0],
                indexToken,
                isLong
            );
            uint256 positionSize = vaultPosition[0];
            uint256 positionCollateral = vaultPosition[1];

            sizeDelta = (sizeDelta * ratio) / ratioDenominator; // most important for closing
            if (sizeDelta > positionSize) sizeDelta = positionSize;
            collateralDelta = (collateralDelta * ratio) / ratioDenominator;
            if (collateralDelta > positionCollateral)
                collateralDelta = positionCollateral;

            minOut = (minOut * ratio) / (ratioDenominator + slippage); // decreased due to price impact
        }

        uint256 acceptablePrice;
        {
            uint256 refPrice;
            uint256 priceBasisPoints;
            uint256 priceBasisPointsDivisor = 10000;
            if (isLong) {
                refPrice = gmxVault.getMinPrice(indexToken);
                priceBasisPoints = priceBasisPointsDivisor - priceAllowedSlippage;
            } else {
                refPrice = gmxVault.getMaxPrice(indexToken);
                priceBasisPoints = priceBasisPointsDivisor + priceAllowedSlippage;
            }
            acceptablePrice = (refPrice * priceBasisPoints) / priceBasisPointsDivisor;
        }

        (bool success, bytes memory data) = gmxPositionRouter.call{
            value: executionFee
        }(
            abi.encodeWithSelector(
                IGmxPositionRouter.createDecreasePosition.selector,
                path,
                indexToken,
                collateralDelta,
                sizeDelta,
                isLong,
                address(this), // receiver
                acceptablePrice,
                minOut,
                executionFee,
                false, // withdrawETH
                address(0) // callbackTarget
            )
        );

        if (!success) {
            revert CreateDecreasePositionFail(_getRevertMsg(data));
        }
        emit CreateDecreasePosition(address(this), bytes32(data));
        return (true, ratio_);
    }

    /// /// /// ///
    /// Orders
    /// /// /// ///

    /*
    @notice Creates new order to open or increase position
    @param tradeData must contain parameters:
        path:            [collateralToken] or [tokenIn, collateralToken] if a swap is needed
        amountIn:        the amount of tokenIn to deposit as collateral
        indexToken:      the address of the token to long or short
        minOut:          the min amount of collateralToken to swap for (can be zero if no swap is required)
        sizeDelta:       the USD value of the change in position size  (scaled 1e30)
        isLong:          whether to long or short position
        triggerPrice:    the price at which the order should be executed
        triggerAboveThreshold:
            in terms of Long position:
                'false' for creating new Long order
            in terms of Short position:
                'true' for creating new Short order

    Additional params for increasing position
        collateralToken: the collateral token (must be path[path.length-1] )
        executionFee:   can be set to OrderBook.minExecutionFee
        shouldWrap:     true if 'tokenIn' is native and should be wrapped
    @return bool - Returns 'true' if order was successfully created
    @return ratio_ - Value for scaling amounts from TraderWallet to UsersVault
    */
    function _createIncreaseOrder(
        bool isTraderWallet,
        address traderWallet,
        address usersVault,
        uint256 ratio,
        bytes memory tradeData
    ) internal returns (bool, uint256 ratio_) {
        IncreaseOrderLocalVars memory vars;
        (
            vars.path,
            vars.amountIn,
            vars.indexToken,
            vars.minOut,
            vars.sizeDelta,
            vars.isLong,
            vars.triggerPrice,
            vars.triggerAboveThreshold
        ) = abi.decode(
            tradeData,
            (address[], uint256, address, uint256, uint256, bool, uint256, bool)
        );
        uint256 executionFee = IGmxOrderBook(gmxOrderBook).minExecutionFee();
        if (address(this).balance < executionFee)
            revert InsufficientEtherBalance();

        address collateralToken;
        if (vars.isLong) {
            collateralToken = vars.indexToken;
        } else {
            collateralToken = vars.path[vars.path.length - 1];
        }

        if (isTraderWallet) {
            // only one check is enough
            if (
                !_validateTradeTokens(
                    traderWallet,
                    collateralToken,
                    vars.indexToken,
                    vars.isLong
                )
            ) {
                revert NotSupportedTokens(collateralToken, vars.indexToken);
            }
            if (!_validateIncreaseOrder(traderWallet)) {
                revert TooManyOrders();
            }

            // calculate ratio for UserVault based on balances of tokenIn (path[0])
            uint256 traderBalance = IERC20Upgradeable(vars.path[0]).balanceOf(
                traderWallet
            );
            uint256 vaultBalance = IERC20Upgradeable(vars.path[0]).balanceOf(usersVault);
            ratio_ = vaultBalance.mulDiv(
                ratioDenominator,
                traderBalance,
                MathUpgradeable.Rounding.Up
            );
        } else {
            if (!_validateIncreaseOrder(usersVault)) {
                revert TooManyOrders();
            }
            // scaling for Vault execution
            vars.amountIn = (vars.amountIn * ratio) / ratioDenominator;
            uint256 amountInAvailable = IERC20Upgradeable(vars.path[0]).balanceOf(
                address(this)
            );
            if (amountInAvailable < vars.amountIn)
                vars.amountIn = amountInAvailable;
            vars.sizeDelta = (vars.sizeDelta * ratio) / ratioDenominator;
            vars.minOut = (vars.minOut * ratio) / (ratioDenominator + slippage); // decreased due to price impact
        }

        _checkUpdateAllowance(vars.path[0], address(gmxRouter), vars.amountIn);

        (bool success, bytes memory data) = gmxOrderBook.call{
            value: executionFee
        }(
            abi.encodeWithSelector(
                IGmxOrderBook.createIncreaseOrder.selector,
                vars.path,
                vars.amountIn,
                vars.indexToken,
                vars.minOut,
                vars.sizeDelta,
                collateralToken,
                vars.isLong,
                vars.triggerPrice,
                vars.triggerAboveThreshold,
                executionFee,
                false // 'shouldWrap'
            )
        );

        if (!success) {
            revert CreateIncreasePositionOrderFail(_getRevertMsg(data));
        }
        return (true, ratio_);
    }

    /*
    @notice Updates exist increase order
    @param tradeData must contain parameters:
        orderIndexes:   the array with Wallet and Vault indexes of the exist order indexes to update
                        [0, 1]: 0 - Wallet, 1 - Vault
        sizeDelta:       the USD value of the change in position size  (scaled 1e30)
        triggerPrice:    the price at which the order should be executed
        triggerAboveThreshold:
            in terms of Long position:
                'false' for creating new Long order
            in terms of Short position:
                'true' for creating new Short order

    @return bool - Returns 'true' if order was successfully updated
    @return ratio_ - Value for scaling amounts from TraderWallet to UsersVault
    */
    function _updateIncreaseOrder(
        bool isTraderWallet,
        address traderWallet,
        address usersVault,
        uint256 ratio,
        bytes memory tradeData
    ) internal returns (bool, uint256 ratio_) {
        (
            uint256[] memory orderIndexes,
            uint256 sizeDelta,
            uint256 triggerPrice,
            bool triggerAboveThreshold
        ) = abi.decode(tradeData, (uint256[], uint256, uint256, bool));

        uint256 orderIndex;

        if (isTraderWallet) {
            // calculate ratio for UserVault based on sizes of current orders
            IGmxOrderBook.IncreaseOrder memory walletOrder = _getIncreaseOrder(
                traderWallet,
                orderIndexes[0]
            );
            IGmxOrderBook.IncreaseOrder memory vaultOrder = _getIncreaseOrder(
                usersVault,
                orderIndexes[1]
            );
            ratio_ = vaultOrder.sizeDelta.mulDiv(
                ratioDenominator,
                walletOrder.sizeDelta,
                MathUpgradeable.Rounding.Down
            );

            orderIndex = orderIndexes[0]; // first for traderWallet, second for usersVault
        } else {
            // scaling for Vault execution
            sizeDelta = (sizeDelta * ratio) / ratioDenominator;
            orderIndex = orderIndexes[1]; // first for traderWallet, second for usersVault
        }

        IGmxOrderBook(gmxOrderBook).updateIncreaseOrder(
            orderIndex,
            sizeDelta,
            triggerPrice,
            triggerAboveThreshold
        );
        return (true, ratio_);
    }

    /*
    @notice Cancels exist increase order
    @param isTraderWallet The flag, 'true' if caller is TraderWallet (and it will calculate ratio for UsersVault)
    @param tradeData must contain parameters:
        orderIndexes:  the array with Wallet and Vault indexes of the exist orders to update
    @return bool - Returns 'true' if order was canceled
    @return ratio_ - Unused value
    */
    function _cancelIncreaseOrder(
        bool isTraderWallet,
        bytes memory tradeData
    ) internal returns (bool, uint256 ratio_) {
        uint256[] memory orderIndexes = abi.decode(tradeData, (uint256[]));

        // default trader Wallet value
        uint256 orderIndex;
        if (isTraderWallet) {
            // value for Wallet
            orderIndex = orderIndexes[0];
        } else {
            // value for Vault
            orderIndex = orderIndexes[1];
        }

        IGmxOrderBook(gmxOrderBook).cancelIncreaseOrder(orderIndex);
        return (true, ratio_);
    }

    /*
    @notice Creates new order to close or decrease position
            Also can be used to create (partial) stop-loss or take-profit orders
    @param tradeData must contain parameters:
        indexToken:      the address of the token that was longed (or shorted)
        sizeDelta:       the USD value of the change in position size (scaled to 1e30)
        collateralToken: the collateral token address
        collateralDelta: the amount of collateral in USD value to withdraw (scaled to 1e30)
        isLong:          whether the position is a long or short
        triggerPrice:    the price at which the order should be executed
        triggerAboveThreshold:
            in terms of Long position:
                'true' for take-profit orders, 'false' for stop-loss orders
            in terms of Short position:
                'false' for take-profit orders', true' for stop-loss orders
    @return bool - Returns 'true' if order was successfully created
    @return ratio_ - Value for scaling amounts from TraderWallet to UsersVault
    */
    function _createDecreaseOrder(
        bool isTraderWallet,
        address traderWallet,
        address usersVault,
        uint256 ratio,
        bytes memory tradeData
    ) internal returns (bool, uint256 ratio_) {
        (
            address indexToken,
            uint256 sizeDelta,
            address collateralToken,
            uint256 collateralDelta,
            bool isLong,
            uint256 triggerPrice,
            bool triggerAboveThreshold
        ) = abi.decode(
                tradeData,
                (address, uint256, address, uint256, bool, uint256, bool)
            );

        // for decrease order gmx requires strict: 'msg.value > minExecutionFee'
        // thats why we need to add 1
        uint256 executionFee = IGmxOrderBook(gmxOrderBook).minExecutionFee() +
            1;
        if (address(this).balance < executionFee)
            revert InsufficientEtherBalance();

        if (isTraderWallet) {
            // calculate ratio for UserVault based on size of opened position
            uint256 traderSize = _getPosition(
                traderWallet,
                collateralToken,
                indexToken,
                isLong
            )[0];
            uint256 vaultSize = _getPosition(
                usersVault,
                collateralToken,
                indexToken,
                isLong
            )[0];
            ratio_ = vaultSize.mulDiv(
                ratioDenominator,
                traderSize,
                MathUpgradeable.Rounding.Up
            );
        } else {
            // scaling for Vault
            uint256[] memory vaultPosition = _getPosition(
                usersVault,
                collateralToken,
                indexToken,
                isLong
            );
            uint256 positionSize = vaultPosition[0];
            uint256 positionCollateral = vaultPosition[1];

            // rounding Up and then check amounts
            sizeDelta = sizeDelta.mulDiv(
                ratio,
                ratioDenominator,
                MathUpgradeable.Rounding.Up
            ); // value important for closing
            if (sizeDelta > positionSize) sizeDelta = positionSize;
            collateralDelta = collateralDelta.mulDiv(
                ratio,
                ratioDenominator,
                MathUpgradeable.Rounding.Up
            );
            if (collateralDelta > positionCollateral)
                collateralDelta = positionCollateral;
        }

        (bool success, bytes memory data) = gmxOrderBook.call{
            value: executionFee
        }(
            abi.encodeWithSelector(
                IGmxOrderBook.createDecreaseOrder.selector,
                indexToken,
                sizeDelta,
                collateralToken,
                collateralDelta,
                isLong,
                triggerPrice,
                triggerAboveThreshold
            )
        );

        if (!success) {
            revert CreateDecreasePositionOrderFail(_getRevertMsg(data));
        }
        return (true, ratio_);
    }

    /*
    @notice Updates exist decrease order
    @param tradeData must contain parameters:
        orderIndexes:   the array with Wallet and Vault indexes of the exist order indexes to update
                        [0, 1]: 0 - Wallet, 1 - Vault
        collateralDelta: the amount of collateral in USD value to withdraw (scaled to 1e30)
        sizeDelta:       the USD value of the change in position size  (scaled 1e30)
        triggerPrice:    the price at which the order should be executed
        triggerAboveThreshold:
            in terms of Long position:
                'true' for take-profit orders, 'false' for stop-loss orders
            in terms of Short position:
                'false' for take-profit orders', true' for stop-loss orders

    @return bool - Returns 'true' if order was successfully updated
    @return ratio_ - Value for scaling amounts from TraderWallet to UsersVault
    */
    function _updateDecreaseOrder(
        bool isTraderWallet,
        address traderWallet,
        address usersVault,
        uint256 ratio,
        bytes memory tradeData
    ) internal returns (bool, uint256 ratio_) {
        (
            uint256[] memory orderIndexes,
            uint256 collateralDelta,
            uint256 sizeDelta,
            uint256 triggerPrice,
            bool triggerAboveThreshold
        ) = abi.decode(tradeData, (uint256[], uint256, uint256, uint256, bool));

        uint256 orderIndex;

        if (isTraderWallet) {
            // calculate ratio for UserVault based on sizes of current orders
            IGmxOrderBook.DecreaseOrder memory walletOrder = _getDecreaseOrder(
                traderWallet,
                orderIndexes[0]
            );
            IGmxOrderBook.DecreaseOrder memory vaultOrder = _getDecreaseOrder(
                usersVault,
                orderIndexes[1]
            );
            ratio_ = vaultOrder.sizeDelta.mulDiv(
                ratioDenominator,
                walletOrder.sizeDelta,
                MathUpgradeable.Rounding.Up
            );

            orderIndex = orderIndexes[0]; // first for traderWallet, second for usersVault
        } else {
            // scaling for Vault execution
            // get current position
            IGmxOrderBook.DecreaseOrder memory vaultOrder = _getDecreaseOrder(
                usersVault,
                orderIndexes[1]
            );
            // rounding Up and then check amounts
            sizeDelta = sizeDelta.mulDiv(
                ratio,
                ratioDenominator,
                MathUpgradeable.Rounding.Up
            ); // value important for closing
            if (sizeDelta > vaultOrder.sizeDelta)
                sizeDelta = vaultOrder.sizeDelta;
            collateralDelta = collateralDelta.mulDiv(
                ratio,
                ratioDenominator,
                MathUpgradeable.Rounding.Up
            );
            if (collateralDelta > vaultOrder.collateralDelta)
                collateralDelta = vaultOrder.collateralDelta;

            orderIndex = orderIndexes[1]; // first for traderWallet, second for usersVault
        }

        IGmxOrderBook(gmxOrderBook).updateDecreaseOrder(
            orderIndex,
            collateralDelta,
            sizeDelta,
            triggerPrice,
            triggerAboveThreshold
        );
        return (true, ratio_);
    }

    /*
        @notice Cancels exist decrease order
        @param isTraderWallet The flag, 'true' if caller is TraderWallet (and it will calculate ratio for UsersVault)
        @param tradeData must contain parameters:
            orderIndexes:      the array with Wallet and Vault indexes of the exist orders to update
        @return bool - Returns 'true' if order was canceled
        @return ratio_ - Unused value
    */
    function _cancelDecreaseOrder(
        bool isTraderWallet,
        bytes memory tradeData
    ) internal returns (bool, uint256 ratio_) {
        uint256[] memory orderIndexes = abi.decode(tradeData, (uint256[]));

        // default trader Wallet value
        uint256 orderIndex;
        if (isTraderWallet) {
            // value for Wallet
            orderIndex = orderIndexes[0];
        } else {
            // value for Vault
            orderIndex = orderIndexes[1];
        }

        IGmxOrderBook(gmxOrderBook).cancelDecreaseOrder(orderIndex);
        return (true, ratio_);
    }

    function _validateTradeTokens(
        address traderWallet,
        address collateralToken,
        address indexToken,
        bool isLong
    ) internal view returns (bool) {
        if (isLong) {
            address[] memory allowedTradeTokens = ITraderWallet(traderWallet)
                .getAllowedTradeTokens();
            uint256 length = allowedTradeTokens.length;
            for (uint256 i; i < length; ) {
                if (allowedTradeTokens[i] == indexToken) return true;
                unchecked {
                    ++i;
                }
            }
        } else {
            if (
                !ITraderWallet(traderWallet).gmxShortPairs(
                    collateralToken,
                    indexToken
                )
            ) {
                return false;
            }
            return true;
        }
        return false;
    }

    /// @dev account can't keep more than 10 orders because of expensive valuation
    ///      For gas saving check only oldest tenth order
    function _validateIncreaseOrder(
        address account
    ) internal view returns (bool) {
        uint256 latestIndex = IGmxOrderBook(gmxOrderBook).increaseOrdersIndex(
            account
        );
        if (latestIndex >= 10) {
            uint256 tenthIndex = latestIndex - 10;
            IGmxOrderBook.IncreaseOrder memory order = IGmxOrderBook(
                gmxOrderBook
            ).increaseOrders(account, tenthIndex);
            if (order.account != address(0)) {
                return false;
            }
        }
        return true;
    }

    /// @notice Updates allowance amount for token
    function _checkUpdateAllowance(
        address token,
        address spender,
        uint256 amount
    ) internal {
        if (IERC20Upgradeable(token).allowance(address(this), spender) < amount) {
            IERC20Upgradeable(token).forceApprove(spender, amount);
        }
    }

    /// @notice Helper function to track revers in call()
    function _getRevertMsg(
        bytes memory _returnData
    ) internal pure returns (string memory) {
        // If the _res length is less than 68, then the transaction failed silently (without a revert message)
        if (_returnData.length < 68) return "Transaction reverted silently";

        assembly {
            // Slice the sighash.
            _returnData := add(_returnData, 0x04)
        }
        return abi.decode(_returnData, (string)); // All that remains is the revert string
    }

    function _getPosition(
        address account,
        address collateralToken,
        address indexToken,
        bool isLong
    ) internal view returns (uint256[] memory) {
        address[] memory collaterals = new address[](1);
        collaterals[0] = collateralToken;
        address[] memory indexTokens = new address[](1);
        indexTokens[0] = indexToken;
        bool[] memory isLongs = new bool[](1);
        isLongs[0] = isLong;

        return
            IGmxReader(gmxReader).getPositions(
                address(gmxVault),
                account,
                collaterals,
                indexTokens,
                isLongs
            );
    }

    function _getIncreaseOrder(
        address account,
        uint256 index
    ) internal view returns (IGmxOrderBook.IncreaseOrder memory) {
        return IGmxOrderBook(gmxOrderBook).increaseOrders(account, index);
    }

    function _getDecreaseOrder(
        address account,
        uint256 index
    ) internal view returns (IGmxOrderBook.DecreaseOrder memory) {
        return IGmxOrderBook(gmxOrderBook).decreaseOrders(account, index);
    }

    function emergencyDecreasePosition(
        address[] calldata path,
        address indexToken,
        uint256 sizeDelta,
        bool isLong
    ) external {
        uint256 executionFee = IGmxPositionRouter(gmxPositionRouter)
            .minExecutionFee();
        if (address(this).balance < executionFee)
            revert InsufficientEtherBalance();
        uint256 acceptablePrice;
        if (isLong) {
            acceptablePrice = gmxVault.getMinPrice(indexToken);
        } else {
            acceptablePrice = gmxVault.getMaxPrice(indexToken);
        }

        (bool success, bytes memory data) = gmxPositionRouter.call{
            value: executionFee
        }(
            abi.encodeWithSelector(
                IGmxPositionRouter.createDecreasePosition.selector,
                path,
                indexToken,
                0, // collateralDelta
                sizeDelta,
                isLong,
                address(this), // receiver
                acceptablePrice,
                0, // minOut
                executionFee,
                false, // withdrawETH
                address(0) // callbackTarget
            )
        );
        if (!success) {
            revert CreateDecreasePositionFail(_getRevertMsg(data));
        }
        emit CreateDecreasePosition(address(this), bytes32(data));
    }
}

