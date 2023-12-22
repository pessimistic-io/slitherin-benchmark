// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./OwnableInternal.sol";
import "./ERC4626BaseInternal.sol";

import "./OptionMath.sol";

import "./IPremiaPool.sol";

import "./IVault.sol";
import "./IVaultEvents.sol";
import "./VaultStorage.sol";

/**
 * @title Knox Vault Internal Contract
 */

contract VaultInternal is ERC4626BaseInternal, IVaultEvents, OwnableInternal {
    using ABDKMath64x64 for int128;
    using ABDKMath64x64 for uint256;
    using OptionMath for int128;
    using OptionMath for uint256;
    using SafeERC20 for IERC20;
    using VaultStorage for VaultStorage.Layout;

    IERC20 public immutable ERC20;
    IPremiaPool public immutable Pool;

    constructor(bool isCall, address pool) {
        Pool = IPremiaPool(pool);
        IPremiaPool.PoolSettings memory settings = Pool.getPoolSettings();
        address asset = isCall ? settings.underlying : settings.base;
        ERC20 = IERC20(asset);
    }

    /************************************************
     *  ACCESS CONTROL
     ***********************************************/

    /**
     * @dev Throws if called by any account other than the keeper
     */
    modifier onlyKeeper() {
        VaultStorage.Layout storage l = VaultStorage.layout();
        require(msg.sender == l.keeper, "!keeper");
        _;
    }

    /**
     * @dev Throws if called by any account other than the queue
     */
    modifier onlyQueue() {
        VaultStorage.Layout storage l = VaultStorage.layout();
        require(msg.sender == address(l.Queue), "!queue");
        _;
    }

    /**
     * @dev Throws if called while withdrawals are locked
     */
    modifier withdrawalsLocked() {
        VaultStorage.Layout storage l = VaultStorage.layout();

        /**
         * the withdrawal lock is active after the auction has started and deactivated
         * when the auction is processed.
         *
         * when the auction has been processed by the keeper the auctionProcessed flag
         * is set to true, deactivating the lock.
         *
         * when the auction is initialized by the keeper the flag is set to false and
         * the startTime is updated.
         *
         * note, the auction must start for the lock to be reactivated. i.e. if the
         * flag is false but the auction has not started the lock is deactivated.
         *
         *
         *    Auction       Auction      Auction       Auction
         *  Initialized     Started     Processed    Initialized
         *       |             |///Locked///|             |
         *       |             |////////////|             |
         * -------------------------Time--------------------------->
         *
         *
         */

        if (block.timestamp >= l.startTime) {
            require(l.auctionProcessed, "auction has not been processed");
        }
        _;
    }

    /************************************************
     *  VIEW
     ***********************************************/

    /**
     * @notice estimates the total reserved "active" collateral
     * @dev collateral is reserved from the auction to ensure the Vault has sufficent funds to
     * cover the APY fee
     * @return estimated amount of reserved "active" collateral
     */
    function _previewReserves() internal view returns (uint256) {
        VaultStorage.Layout storage l = VaultStorage.layout();
        return l.reserveRate64x64.mulu(_totalCollateral());
    }

    /**
     * @notice calculates the total active vault by deducting the premium from the ERC20 balance
     * @return total active collateral
     */
    function _totalCollateral() internal view returns (uint256) {
        VaultStorage.Layout storage l = VaultStorage.layout();
        // premiums are deducted as they are not considered "active" assets
        return ERC20.balanceOf(address(this)) - l.totalPremium;
    }

    /**
     * @notice calculates the short position value denominated in the collateral asset
     * @return total short position in collateral amount
     */
    function _totalShortAsCollateral() internal view returns (uint256) {
        VaultStorage.Layout storage l = VaultStorage.layout();
        VaultStorage.Option memory lastOption = _lastOption(l);

        uint256 totalShortContracts = _totalShortAsContracts();

        // calculates the value of the vaults short position
        return
            totalShortContracts.fromContractsToCollateral(
                l.isCall,
                l.underlyingDecimals,
                l.baseDecimals,
                lastOption.strike64x64
            );
    }

    /**
     * @notice returns the amount in short contracts underwitten by the vault
     * @return total short contracts
     */
    function _totalShortAsContracts() internal view returns (uint256) {
        VaultStorage.Layout storage l = VaultStorage.layout();
        uint256 shortTokenId = l.options[_lastEpoch(l)].shortTokenId;
        return Pool.balanceOf(address(this), shortTokenId);
    }

    /************************************************
     *  ERC4626 OVERRIDES
     ***********************************************/

    /**
     * @notice calculates the total active assets held by the vault denominated in the collateral asset
     * @return total active asset amount
     */
    function _totalAssets()
        internal
        view
        override(ERC4626BaseInternal)
        returns (uint256)
    {
        VaultStorage.Layout storage l = VaultStorage.layout();
        // totalAssets = totalCollateral + totalShortInCollateral - fee
        // totalAssets = (ERC20Balance - fee) + (totalPremium - fee) + totalShortInCollateral - fee
        // totalAssets = ERC20Balance + totalPremium + totalShortInCollateral - fee
        return _totalCollateral() + _totalShortAsCollateral() - l.fee;
    }

    /**
     * @notice calculate the maximum quantity of base assets which may be withdrawn by given holder
     * @param owner holder of shares to be redeemed
     * @return maxAssets maximum asset mint amount
     */
    function _maxWithdraw(address owner)
        internal
        view
        virtual
        override(ERC4626BaseInternal)
        returns (uint256)
    {
        VaultStorage.Layout storage l = VaultStorage.layout();
        uint256 unredeemed = l.Queue.previewMaxUnredeemed(owner);
        return _convertToAssets(unredeemed + _balanceOf(owner));
    }

    /**
     * @notice calculate the maximum quantity of shares which may be redeemed by given holder
     * @param owner holder of shares to be redeemed
     * @return maxShares maximum share redeem amount
     */
    function _maxRedeem(address owner)
        internal
        view
        virtual
        override(ERC4626BaseInternal)
        returns (uint256)
    {
        VaultStorage.Layout storage l = VaultStorage.layout();
        uint256 unredeemed = l.Queue.previewMaxUnredeemed(owner);
        return unredeemed + _balanceOf(owner);
    }

    /**
     * @notice execute a withdrawal of assets on behalf of given address
     * @dev owner must approve vault to redeem claim tokens
     * @dev this function may not be called while the auction is in progress
     * @param assetAmount quantity of assets to withdraw
     * @param receiver recipient of assets resulting from withdrawal
     * @param owner holder of shares to be redeemed
     * @return shareAmount quantity of shares to redeem
     */
    function _withdraw(
        uint256 assetAmount,
        address receiver,
        address owner
    ) internal virtual override(ERC4626BaseInternal) returns (uint256) {
        require(
            assetAmount <= _maxWithdraw(owner),
            "ERC4626: maximum amount exceeded"
        );

        uint256 shareAmount = _previewWithdraw(assetAmount);

        _withdraw(msg.sender, receiver, owner, assetAmount, shareAmount);

        return shareAmount;
    }

    /**
     * @notice execute a redemption of shares on behalf of given address
     * @dev owner must approve vault to redeem claim tokens
     * @dev this function may not be called while the auction is in progress
     * @param shareAmount quantity of shares to redeem
     * @param receiver recipient of assets resulting from withdrawal
     * @param owner holder of shares to be redeemed
     * @return assetAmount quantity of assets to withdraw
     */
    function _redeem(
        uint256 shareAmount,
        address receiver,
        address owner
    ) internal virtual override(ERC4626BaseInternal) returns (uint256) {
        require(
            shareAmount <= _maxRedeem(owner),
            "ERC4626: maximum amount exceeded"
        );

        uint256 assetAmount = _previewRedeem(shareAmount);

        _withdraw(msg.sender, receiver, owner, assetAmount, shareAmount);

        return assetAmount;
    }

    /**
     * @notice exchange shares for assets on behalf of given address
     * @param caller transaction operator for purposes of allowance verification
     * @param receiver recipient of assets resulting from withdrawal
     * @param owner holder of shares to be redeemed
     * @param assetAmount quantity of assets to withdraw
     * @param shareAmount quantity of shares to redeem
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assetAmount,
        uint256 shareAmount
    ) private {
        VaultStorage.Layout storage l = VaultStorage.layout();

        // prior to withdrawing, the vault will redeem all available claim tokens
        // in exchange for the pro-rata vault shares
        l.Queue.redeemMax(receiver, owner);

        require(l.epoch > 0, "cannot withdraw on epoch 0");

        if (caller != owner) {
            // if the owner is not equal to the caller, approve the caller
            // to spend up to the allowance
            uint256 allowance = _allowance(owner, caller);

            require(
                allowance >= shareAmount,
                "ERC4626: share amount exceeds allowance"
            );

            unchecked {_approve(owner, caller, allowance - shareAmount);}
        }

        _beforeWithdraw(owner, assetAmount, shareAmount);

        // burns vault shares held by owner
        _burn(owner, shareAmount);

        // aggregate the total assets withdrawn during the current epoch
        l.totalWithdrawals += assetAmount;

        // removes any reserved liquidty from pool in the event an option has been exercised
        _withdrawReservedLiquidity(l);

        // LPs may withdraw funds at any time and receive a proportion of the assets held in
        // the vault. this means that a withdrawal can be mixture of collateral assets and
        // short contracts, 100% collateral, or 100% short contracts. if a user wishes to
        // exit without exposure to a short position, they should wait until the vault holds
        // no short contracts, or withdraw and reassign their short contracts via Premia's
        // contracts.

        // calculate the collateral amount and short contract amount distribution
        (uint256 collateralAmount, uint256 shortContracts) =
            _previewDistributions(l, assetAmount);

        // transfers the collateral and short contracts to the receiver
        _transferCollateralAndShortAssets(
            _lastEpoch(l),
            collateralAmount,
            shortContracts,
            _lastOption(l).shortTokenId,
            receiver
        );

        emit Withdraw(caller, receiver, owner, assetAmount, shareAmount);
    }

    /************************************************
     *  WITHDRAW HELPERS
     ***********************************************/

    /**
     * @notice returns the total amount of collateral and short contracts to distribute
     * @param l vault storage layout
     * @param assetAmount quantity of assets to withdraw
     * @return distribution amount in collateral asset
     * @return distribution amount in the short contracts
     */
    function _previewDistributions(
        VaultStorage.Layout storage l,
        uint256 assetAmount
    ) internal view returns (uint256, uint256) {
        uint256 totalAssets = _totalAssets();

        uint256 collateralAmount =
            _calculateDistributionAmount(
                assetAmount,
                _totalCollateral(),
                totalAssets
            );

        VaultStorage.Option memory lastOption = _lastOption(l);

        uint256 totalShortAsCollateral = _totalShortAsCollateral();

        // calculates the distribution of short contracts denominated as collateral
        uint256 shortAsCollateral =
            _calculateDistributionAmount(
                assetAmount,
                totalShortAsCollateral,
                totalAssets
            );

        // converts the collateral amount back to short contracts.
        uint256 shortContracts =
            shortAsCollateral.fromCollateralToContracts(
                l.isCall,
                l.baseDecimals,
                lastOption.strike64x64
            );

        return (collateralAmount, shortContracts);
    }

    /**
     * @notice calculates the distribution amount
     * @param assetAmount quantity of assets to withdraw
     * @param collateralAmount quantity of asset collateral held by vault
     * @param totalAssets total amount of assets held by vault, denominated in collateral asset
     * @return distribution amount, denominated in the collateral asset
     */
    function _calculateDistributionAmount(
        uint256 assetAmount,
        uint256 collateralAmount,
        uint256 totalAssets
    ) private pure returns (uint256) {
        // calculates the ratio of collateral to total assets
        int128 assetRatio64x64 =
            collateralAmount > 0
                ? collateralAmount.divu(totalAssets)
                : int128(0);
        // calculates the amount of the asset which should be withdrawn
        return assetRatio64x64 > 0 ? assetRatio64x64.mulu(assetAmount) : 0;
    }

    /**
     * @notice transfers collateral and short contract tokens to receiver
     * @param epoch vault storage layout
     * @param collateralAmount quantity of asset collateral to deduct fees from
     * @param shortContracts quantity of short contracts to deduct fees from
     * @param shortTokenId quantity of short contracts to deduct fees from
     * @param receiver quantity of short contracts to deduct fees from
     */
    function _transferCollateralAndShortAssets(
        uint64 epoch,
        uint256 collateralAmount,
        uint256 shortContracts,
        uint256 shortTokenId,
        address receiver
    ) private {
        if (collateralAmount > 0) {
            // transfers collateral to receiver
            ERC20.safeTransfer(receiver, collateralAmount);
        }

        if (shortContracts > 0) {
            // transfers short contracts to receiver
            Pool.safeTransferFrom(
                address(this),
                receiver,
                shortTokenId,
                shortContracts,
                ""
            );
        }

        emit DistributionSent(
            epoch,
            collateralAmount,
            shortContracts,
            receiver
        );
    }

    /************************************************
     *  ADMIN HELPERS
     ***********************************************/

    /**
     * @notice sets the parameters for the next option to be sold
     * @param l vault storage layout
     * @return the next option to be sold
     */
    function _setOptionParameters(VaultStorage.Layout storage l)
        internal
        returns (VaultStorage.Option memory)
    {
        // sets the expiry for the next Friday
        uint64 expiry = uint64(_getNextFriday(block.timestamp));

        // calculates the delta strike price
        int128 strike64x64;

        try
            l.Pricer.getDeltaStrikePrice64x64(l.isCall, expiry, l.delta64x64)
        returns (int128 _strike64x64) {
            strike64x64 = l.Pricer.snapToGrid64x64(l.isCall, _strike64x64);
        } catch Error(string memory message) {
            emit Log(message);
            strike64x64 = 0;
        }

        // sets parameters for the next option
        VaultStorage.Option storage option = l.options[l.epoch];
        option.expiry = expiry;
        option.strike64x64 = strike64x64;

        TokenType longTokenType =
            l.isCall ? TokenType.LONG_CALL : TokenType.LONG_PUT;

        // get the formatted long token id
        option.longTokenId = _formatTokenId(longTokenType, expiry, strike64x64);

        TokenType shortTokenType =
            l.isCall ? TokenType.SHORT_CALL : TokenType.SHORT_PUT;

        // get the formatted short token id
        option.shortTokenId = _formatTokenId(
            shortTokenType,
            expiry,
            strike64x64
        );

        emit OptionParametersSet(
            l.epoch,
            option.expiry,
            option.strike64x64,
            option.longTokenId,
            option.shortTokenId
        );

        return option;
    }

    /**
     * @notice collects performance fees on epoch net income
     * @dev auction must be processed before fees can be collected, do not call
     * this function on epoch 0
     * @param l vault storage layout
     */
    function _collectPerformanceFee(VaultStorage.Layout storage l) internal {
        // pool must return all available "reserved liquidity" to the vault after the
        // option expires and before performance fee can be collected
        _withdrawReservedLiquidity(l);

        // adjusts total "active" assets to account for assets withdrawn during the epoch
        uint256 adjustedTotalAssets = _totalAssets() + l.totalWithdrawals;

        uint256 gain;
        uint256 loss;

        // collect performance fee ONLY if the vault returns a positive net income (gain)
        if (adjustedTotalAssets >= l.lastTotalAssets) {
            // option expires ATM, at most, the vault will take a fee from the premiums
            // collected during the last auction
            gain = l.totalPremium;
        } else {
            uint256 netLoss = l.lastTotalAssets - adjustedTotalAssets;

            if (l.totalPremium > netLoss) {
                // option expires ITM but the vault breaks-even, the gain is the amount
                // remaining from the premium (gain = premium - net_loss)
                gain = l.totalPremium - netLoss;
            } else {
                // option expires far-ITM the premiums is lost, and the net income
                // is negative (loss)
                loss = netLoss - l.totalPremium;
            }
        }

        if (gain > 0) {
            // calculate the performance fee
            l.fee = l.performanceFee64x64.mulu(gain);

            // remove the fee from the premium
            l.totalPremium -= l.fee;

            // send collected fee to recipient wallet
            ERC20.safeTransfer(l.feeRecipient, l.fee);
        } else {
            // if the net income is negative, the option expired ITM past break-even
            // and the vault took a loss so we do not collect performance fee
            l.totalPremium = 0;
        }

        l.totalWithdrawals = 0;

        emit PerformanceFeeCollected(_lastEpoch(l), gain, loss, l.fee);
    }

    /**
     * @notice removes reserved liquidity from Premia pool
     * @param l vault storage layout
     */
    function _withdrawReservedLiquidity(VaultStorage.Layout storage l)
        internal
    {
        // gets the vaults reserved liquidity balance
        uint256 reservedLiquidity =
            Pool.balanceOf(
                address(this),
                l.isCall
                    ? uint256(TokenType.UNDERLYING_RESERVED_LIQ) << 248
                    : uint256(TokenType.BASE_RESERVED_LIQ) << 248
            );

        if (reservedLiquidity > 0) {
            // remove reserved liquidity from the pool, if available
            Pool.withdraw(reservedLiquidity, l.isCall);
        }

        emit ReservedLiquidityWithdrawn(l.epoch, reservedLiquidity);
    }

    /************************************************
     *  PREMIA HELPERS
     ***********************************************/

    // Premia ERC1155 token types
    enum TokenType {
        UNDERLYING_FREE_LIQ,
        BASE_FREE_LIQ,
        UNDERLYING_RESERVED_LIQ,
        BASE_RESERVED_LIQ,
        LONG_CALL,
        SHORT_CALL,
        LONG_PUT,
        SHORT_PUT
    }

    /**
     * @notice calculate ERC1155 token id for given option parameters
     * @param tokenType TokenType enum
     * @param maturity timestamp of option maturity
     * @param strike64x64 64x64 fixed point representation of strike price
     * @return tokenId token id
     */
    function _formatTokenId(
        TokenType tokenType,
        uint64 maturity,
        int128 strike64x64
    ) internal pure returns (uint256 tokenId) {
        tokenId =
            (uint256(tokenType) << 248) +
            (uint256(maturity) << 128) +
            uint256(int256(strike64x64));
    }

    /************************************************
     *  HELPERS
     ***********************************************/

    /**
     * @notice returns the last epoch
     * @param l vault storage layout
     * @return last epoch
     */
    function _lastEpoch(VaultStorage.Layout storage l)
        internal
        view
        returns (uint64)
    {
        return l.epoch > 0 ? l.epoch - 1 : 0;
    }

    /**
     * @notice returns option from the last epoch
     * @param l vault storage layout
     * @return option from last epoch
     */
    function _lastOption(VaultStorage.Layout storage l)
        internal
        view
        returns (VaultStorage.Option memory)
    {
        return l.options[_lastEpoch(l)];
    }

    /**
     * Assuming a standard calendar week (Sunday - Saturday).
     *
     * getFriday will always return the next approaching Friday.
     * getNextFriday will always return the Friday after getFriday.
     *
     * Examples:
     * getFriday(2022-08-18T09:00:00Z) -> 2022-08-19T08:00:00Z
     * getNextFriday(2022-08-18T09:00:00Z) -> 2022-08-26T08:00:00Z
     *
     * getFriday(2022-08-19T07:00:00Z) -> 2022-08-19T08:00:00Z
     * getNextFriday(2022-08-19T07:00:00Z) -> 2022-08-26T08:00:00Z
     *
     * getFriday(2022-08-19T08:00:00Z) -> 2022-08-26T08:00:00Z
     * getNextFriday(2022-08-19T08:00:00Z) -> 2022-09-02T08:00:00Z
     *
     * getFriday(2022-08-20T09:00:00Z) -> 2022-08-26T08:00:00Z
     * getNextFriday(2022-08-20T09:00:00Z) -> 2022-09-02T08:00:00Z
     *
     * getFriday(2022-08-21T09:00:00Z) -> 2022-08-26T08:00:00Z
     * getNextFriday(2022-08-21T09:00:00Z) -> 2022-09-02T08:00:00Z
     */

    /**
     * @notice returns the next approaching Friday 8AM UTC timestamp
     * @param timestamp is the current timestamp
     * @return Friday 8am UTC timestamp
     */
    function _getFriday(uint256 timestamp) internal pure returns (uint256) {
        // dayOfWeek = 0 (sunday) - 6 (saturday)
        uint256 dayOfWeek = ((timestamp / 1 days) + 4) % 7;
        uint256 nextFriday = timestamp + ((7 + 5 - dayOfWeek) % 7) * 1 days;
        uint256 friday8am = nextFriday - (nextFriday % (24 hours)) + (8 hours);

        // if the timestamp is past Friday 8am UTC, return the next calendar
        // week Friday
        if (timestamp >= friday8am) {
            friday8am += 7 days;
        }
        return friday8am;
    }

    /**
     * @notice returns the next approaching Friday 8AM UTC timestamp + 7 days
     * @param timestamp is the current timestamp
     * @return Friday 8am UTC timestamp
     */
    function _getNextFriday(uint256 timestamp) internal pure returns (uint256) {
        return _getFriday(timestamp) + 7 days;
    }
}

