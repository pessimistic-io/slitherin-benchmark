// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

import { AddressUpgradeable } from "./AddressUpgradeable.sol";
import { SafeMathUpgradeable } from "./SafeMathUpgradeable.sol";
import { SignedSafeMathUpgradeable } from "./SignedSafeMathUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { IUniswapV3Pool } from "./IUniswapV3Pool.sol";
import { IUniswapV3MintCallback } from "./IUniswapV3MintCallback.sol";
import { IUniswapV3SwapCallback } from "./IUniswapV3SwapCallback.sol";
import { PerpMath } from "./PerpMath.sol";
import { OwnerPausable } from "./OwnerPausable.sol";
import { IERC20Metadata } from "./IERC20Metadata.sol";
import { IVault } from "./IVault.sol";
import { IVPool } from "./IVPool.sol";
import { IIndexPrice } from "./IIndexPrice.sol";
import { IClearingHouseConfig } from "./IClearingHouseConfig.sol";
import { IAccountBalance } from "./IAccountBalance.sol";
import { IInsuranceFund } from "./IInsuranceFund.sol";
import { IBaseToken } from "./IBaseToken.sol";
import { IIndexPrice } from "./IIndexPrice.sol";
import { IDelegateApproval } from "./IDelegateApproval.sol";
import { BaseRelayRecipient } from "./BaseRelayRecipient.sol";
import { ClearingHouseStorage } from "./ClearingHouseStorage.sol";
import { BlockContext } from "./BlockContext.sol";
import { IClearingHouse } from "./IClearingHouse.sol";
import { ClearingHouseLogic } from "./ClearingHouseLogic.sol";
import { GenericLogic } from "./GenericLogic.sol";
import { IMarketRegistry } from "./IMarketRegistry.sol";
import { DataTypes } from "./DataTypes.sol";
import { UniswapV3Broker } from "./UniswapV3Broker.sol";

// never inherit any new stateful contract. never change the orders of parent stateful contracts
contract ClearingHouse is
    IUniswapV3MintCallback,
    IUniswapV3SwapCallback,
    IClearingHouse,
    BlockContext,
    ReentrancyGuardUpgradeable,
    OwnerPausable,
    BaseRelayRecipient,
    ClearingHouseStorage
{
    using AddressUpgradeable for address;
    using SafeMathUpgradeable for uint256;
    using SignedSafeMathUpgradeable for int256;
    using PerpMath for uint256;
    using PerpMath for uint160;
    using PerpMath for uint128;
    using PerpMath for int256;

    //
    // STRUCT
    //

    struct InternalRepegParams {
        uint160 oldSqrtMarkPrice;
        uint256 oldMarkPrice;
        uint160 newSqrtMarkPrice;
        uint256 newMarkPrice;
        uint256 spotPrice;
        uint160 sqrtSpotPrice;
        int256 oldDeltaBase;
        uint256 newDeltaBase;
        uint256 oldLongPositionSize;
        uint256 oldShortPositionSize;
        uint256 oldDeltaQuote;
    }

    //
    // MODIFIER
    //

    modifier checkDeadline(uint256 deadline) {
        // transaction expires
        require(_blockTimestamp() <= deadline, "CH_TE");
        _;
    }

    modifier onlyMaker() {
        // only maker
        require(_msgSender() == _maker, "CH_OM");
        _;
    }

    modifier checkSwapCallback() {
        // only exchange
        require(_msgSender() == _vPool, "CH_OE");
        _;
    }

    modifier checkMintCallback() {
        address pool = _msgSender();
        address baseToken = IUniswapV3Pool(pool).token0();
        // UCB_FCV: failed callback validation
        require(pool == IMarketRegistry(_marketRegistry).getPool(baseToken), "UCB_FCV");
        _;
    }

    //
    // EXTERNAL NON-VIEW
    //

    /// @dev this function is public for testing
    // solhint-disable-next-line func-order
    function initialize(
        address clearingHouseConfigArg,
        address vaultArg,
        address quoteTokenArg,
        address uniV3FactoryArg,
        address exchangeArg,
        address accountBalanceArg,
        address marketRegistryArg,
        address insuranceFundArg,
        address platformFundArg,
        address makerArg
    ) public initializer {
        // CH_VANC: Vault address is not contract
        _isContract(vaultArg, "CH_VANC");
        // CH_QANC: QuoteToken address is not contract
        _isContract(quoteTokenArg, "CH_QANC");
        // CH_QDN18: QuoteToken decimals is not 18
        require(IERC20Metadata(quoteTokenArg).decimals() == 18, "CH_QDN18");
        // CH_UANC: UniV3Factory address is not contract
        _isContract(uniV3FactoryArg, "CH_UANC");
        // ClearingHouseConfig address is not contract
        _isContract(clearingHouseConfigArg, "CH_CCNC");
        // AccountBalance is not contract
        _isContract(accountBalanceArg, "CH_ABNC");
        // CH_ENC: Exchange is not contract
        _isContract(exchangeArg, "CH_ENC");
        // CH_IFANC: InsuranceFund address is not contract
        _isContract(insuranceFundArg, "CH_IFANC");

        __ReentrancyGuard_init();
        __OwnerPausable_init();

        _clearingHouseConfig = clearingHouseConfigArg;
        _vault = vaultArg;
        _quoteToken = quoteTokenArg;
        _uniswapV3Factory = uniV3FactoryArg;
        _vPool = exchangeArg;
        _accountBalance = accountBalanceArg;
        _marketRegistry = marketRegistryArg;
        _insuranceFund = insuranceFundArg;
        _platformFund = platformFundArg;
        _maker = makerArg;

        _settlementTokenDecimals = IVault(_vault).decimals();
    }

    /// @dev remove to reduce bytecode size, might add back when we need it
    // // solhint-disable-next-line func-order
    // function setTrustedForwarder(address trustedForwarderArg) external onlyOwner {
    //     // CH_TFNC: TrustedForwarder is not contract
    //     require(trustedForwarderArg.isContract(), "CH_TFNC");
    //     // TrustedForwarderUpdated event is emitted in BaseRelayRecipient
    //     _setTrustedForwarder(trustedForwarderArg);
    // }

    function setDelegateApproval(address delegateApprovalArg) external onlyOwner {
        // CH_DANC: DelegateApproval is not contract
        require(delegateApprovalArg.isContract(), "CH_DANC");
        _delegateApproval = delegateApprovalArg;
        emit DelegateApprovalChanged(delegateApprovalArg);
    }

    function setPlatformFund(address platformFundArg) external onlyOwner {
        _platformFund = platformFundArg;
        emit PlatformFundChanged(platformFundArg);
    }

    function setRewardMiner(address rewardMinerArg) external onlyOwner {
        require(rewardMinerArg.isContract(), "CH_RMNC");
        _rewardMiner = rewardMinerArg;
        emit RewardMinerChanged(rewardMinerArg);
    }

    /// @inheritdoc IClearingHouse
    function addLiquidity(
        DataTypes.AddLiquidityParams memory params
    )
        public
        override
        whenNotPaused
        nonReentrant
        checkDeadline(params.deadline)
        onlyMaker
        returns (
            // check onlyLiquidityAdmin
            DataTypes.AddLiquidityResponse memory
        )
    {
        return GenericLogic.addLiquidity(address(this), params);
    }

    /// @inheritdoc IClearingHouse
    function removeLiquidity(
        DataTypes.RemoveLiquidityParams memory params
    )
        public
        override
        whenNotPaused
        nonReentrant
        checkDeadline(params.deadline)
        onlyMaker
        returns (DataTypes.RemoveLiquidityResponse memory)
    {
        return GenericLogic.removeLiquidity(address(this), params);
    }

    /// @inheritdoc IClearingHouse
    function settleAllFunding(address trader) external override {
        // only vault or trader
        // vault must check msg.sender == trader when calling settleAllFunding
        require(_msgSender() == _vault || _msgSender() == trader, "CH_OVOT");

        address[] memory baseTokens = IAccountBalance(_accountBalance).getBaseTokens(trader);
        uint256 baseTokenLength = baseTokens.length;
        int256 fundingPaymentTotal;
        for (uint256 i = 0; i < baseTokenLength; i++) {
            (, int256 fundingPayment) = GenericLogic.settleFunding(address(this), trader, baseTokens[i]);
            fundingPaymentTotal = fundingPaymentTotal.add(fundingPayment);
        }
        // reward miner
        ClearingHouseLogic.rewardMinerMint(address(this), trader, 0, fundingPaymentTotal.neg256());
    }

    /// @inheritdoc IClearingHouse
    function openPosition(
        DataTypes.OpenPositionParams memory params
    )
        external
        override
        whenNotPaused
        nonReentrant
        checkDeadline(params.deadline)
        returns (uint256 base, uint256 quote)
    {
        // openPosition() is already published, returned types remain the same (without fee)
        (base, quote, ) = _openPositionFor(_msgSender(), params);
        return (base, quote);
    }

    /// @inheritdoc IClearingHouse
    function openPositionFor(
        address trader,
        DataTypes.OpenPositionParams memory params
    )
        external
        override
        whenNotPaused
        nonReentrant
        checkDeadline(params.deadline)
        returns (uint256 base, uint256 quote, uint256 fee)
    {
        // CH_SHNAOPT: Sender Has No Approval to Open Position for Trader
        require(IDelegateApproval(_delegateApproval).canOpenPositionFor(trader, _msgSender()), "CH_SHNAOPT");

        return _openPositionFor(trader, params);
    }

    /// @inheritdoc IClearingHouse
    function closePosition(
        DataTypes.ClosePositionParams memory params
    )
        public
        override
        whenNotPaused
        nonReentrant
        checkDeadline(params.deadline)
        returns (uint256 base, uint256 quote, uint256 fee)
    {
        return ClearingHouseLogic.closePosition(address(this), _msgSender(), params);
    }

    /// @inheritdoc IClearingHouse
    function liquidate(
        address trader,
        address baseToken,
        int256 positionSize
    ) external override whenNotPaused nonReentrant returns (uint256 base, uint256 quote, uint256 fee) {
        // positionSizeToBeLiquidated = 0 means liquidating as much as possible
        return _liquidate(trader, baseToken, positionSize, false);
    }

    /// @inheritdoc IUniswapV3MintCallback
    /// @dev namings here follow Uniswap's convention
    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external override checkMintCallback {
        // input requirement checks:
        //   amount0Owed: here
        //   amount1Owed: here
        //   data: X

        // For caller validation purposes it would be more efficient and more reliable to use
        // "msg.sender" instead of "_msgSender()" as contracts never call each other through GSN.
        // not orderbook
        // require(msg.sender == _orderBook, "CH_NOB");

        UniswapV3Broker.MintCallbackData memory callbackData = abi.decode(data, (UniswapV3Broker.MintCallbackData));

        if (amount0Owed > 0) {
            address token = IUniswapV3Pool(callbackData.pool).token0();
            _requireTransfer(token, callbackData.pool, amount0Owed);
        }
        if (amount1Owed > 0) {
            address token = IUniswapV3Pool(callbackData.pool).token1();
            _requireTransfer(token, callbackData.pool, amount1Owed);
        }
    }

    /// @inheritdoc IUniswapV3SwapCallback
    /// @dev namings here follow Uniswap's convention
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external override checkSwapCallback {
        // input requirement checks:
        //   amount0Delta: here
        //   amount1Delta: here
        //   data: X
        // For caller validation purposes it would be more efficient and more reliable to use
        // "msg.sender" instead of "_msgSender()" as contracts never call each other through GSN.
        // require(msg.sender == _vPool, "CH_OE");

        // swaps entirely within 0-liquidity regions are not supported -> 0 swap is forbidden
        // CH_F0S: forbidden 0 swap
        require((amount0Delta > 0 && amount1Delta < 0) || (amount0Delta < 0 && amount1Delta > 0), "CH_F0S");

        IVPool.SwapCallbackData memory callbackData = abi.decode(data, (IVPool.SwapCallbackData));
        IUniswapV3Pool uniswapV3Pool = IUniswapV3Pool(callbackData.pool);

        // amount0Delta & amount1Delta are guaranteed to be positive when being the amount to be paid
        (address token, uint256 amountToPay) = amount0Delta > 0
            ? (uniswapV3Pool.token0(), uint256(amount0Delta))
            : (uniswapV3Pool.token1(), uint256(amount1Delta));

        // swap
        _requireTransfer(token, callbackData.pool, amountToPay);
    }

    //
    // EXTERNAL VIEW
    //

    /// @inheritdoc IClearingHouse
    function getQuoteToken() external view override returns (address) {
        return _quoteToken;
    }

    /// @inheritdoc IClearingHouse
    function getUniswapV3Factory() external view override returns (address) {
        return _uniswapV3Factory;
    }

    /// @inheritdoc IClearingHouse
    function getClearingHouseConfig() external view override returns (address) {
        return _clearingHouseConfig;
    }

    /// @inheritdoc IClearingHouse
    function getVault() external view override returns (address) {
        return _vault;
    }

    /// @inheritdoc IClearingHouse
    function getVPool() external view override returns (address) {
        return _vPool;
    }

    /// @inheritdoc IClearingHouse
    function getAccountBalance() external view override returns (address) {
        return _accountBalance;
    }

    /// @inheritdoc IClearingHouse
    function getRewardMiner() external view override returns (address) {
        return _rewardMiner;
    }

    /// @inheritdoc IClearingHouse
    function getInsuranceFund() external view override returns (address) {
        return _insuranceFund;
    }

    /// @inheritdoc IClearingHouse
    function getPlatformFund() external view override returns (address) {
        return _platformFund;
    }

    /// @inheritdoc IClearingHouse
    function getDelegateApproval() external view override returns (address) {
        return _delegateApproval;
    }

    function getMaker() external view override returns (address) {
        return _maker;
    }

    function getMarketRegistry() external view override returns (address) {
        return _marketRegistry;
    }

    // /// @inheritdoc IClearingHouse
    // function getAccountValue(address trader) public view override returns (int256) {
    //     return IVault(_vault).getAccountValue(trader).parseSettlementToken(_settlementTokenDecimals);
    // }

    function getLiquidity(address baseToken) external view returns (uint128) {
        address pool = IMarketRegistry(_marketRegistry).getPool(baseToken);
        return UniswapV3Broker.getLiquidity(pool);
    }

    //
    // INTERNAL NON-VIEW
    //

    function _requireTransfer(address token, address to, uint256 amount) internal {
        // CH_TF: Transfer failed
        require(IERC20Metadata(token).transfer(to, amount), "CH_TF");
    }

    function _liquidate(
        address trader,
        address baseToken,
        int256 positionSize,
        bool isForced
    ) internal returns (uint256 base, uint256 quote, uint256 fee) {
        return
            ClearingHouseLogic.liquidate(
                ClearingHouseLogic.InternalLiquidateParams({
                    chAddress: address(this),
                    marketRegistry: _marketRegistry,
                    liquidator: _msgSender(),
                    trader: trader,
                    baseToken: baseToken,
                    positionSizeToBeLiquidated: positionSize,
                    isForced: isForced
                })
            );
    }

    function _openPositionFor(
        address trader,
        DataTypes.OpenPositionParams memory params
    ) internal returns (uint256 base, uint256 quote, uint256 fee) {
        return ClearingHouseLogic.openPositionFor(address(this), trader, params);
    }

    //
    // INTERNAL VIEW
    //

    /// @inheritdoc BaseRelayRecipient
    function _msgSender() internal view override(BaseRelayRecipient, OwnerPausable) returns (address payable) {
        return super._msgSender();
    }

    /// @inheritdoc BaseRelayRecipient
    function _msgData() internal view override(BaseRelayRecipient, OwnerPausable) returns (bytes memory) {
        return super._msgData();
    }

    /// @dev liquidation condition:
    ///      accountValue < sum(abs(positionValue_by_market)) * mmRatio = totalMinimumMarginRequirement
    function isLiquidatable(address trader) external view returns (bool) {
        return GenericLogic.isLiquidatable(address(this), trader);
    }

    function _isContract(address contractArg, string memory errorMsg) internal view {
        require(contractArg.isContract(), errorMsg);
    }

    function isAbleRepeg(address baseToken) public view returns (bool) {
        (uint256 longPositionSize, uint256 shortPositionSize) = IAccountBalance(_accountBalance).getMarketPositionSize(
            baseToken
        );
        if (longPositionSize + shortPositionSize == 0) {
            return true;
        }
        if (!IVPool(_vPool).isOverPriceSpread(baseToken)) {
            return false;
        }
        if (!IVPool(_vPool).isOverPriceSpreadTimestamp(baseToken)) {
            return false;
        }
        return true;
    }

    ///REPEG
    function repeg(address baseToken) external {
        // check isAbleRepeg
        // CH_NRP: not repeg
        require(isAbleRepeg(baseToken), "CH_NRP");
        //settleFundingGlobal
        GenericLogic.settleFundingGlobal(address(this), baseToken);
        //variable
        InternalRepegParams memory repegParams;
        (repegParams.oldSqrtMarkPrice, , , , , , ) = UniswapV3Broker.getSlot0(
            IMarketRegistry(_marketRegistry).getPool(baseToken)
        );
        repegParams.oldMarkPrice = repegParams.oldSqrtMarkPrice.formatSqrtPriceX96ToPriceX96().formatX96ToX10_18();
        repegParams.spotPrice = IIndexPrice(baseToken).getIndexPrice(
            IClearingHouseConfig(_clearingHouseConfig).getTwapInterval()
        );
        repegParams.sqrtSpotPrice = repegParams.spotPrice.formatPriceX10_18ToSqrtPriceX96();

        if (repegParams.spotPrice != repegParams.oldMarkPrice) {
            // check mark price != index price over 10% and over 1 hour
            // calculate delta base (11) of long short -> delta quote (1)
            // for multiplier
            (
                repegParams.oldLongPositionSize,
                repegParams.oldShortPositionSize,
                repegParams.oldDeltaQuote
            ) = GenericLogic.getInfoMultiplier(address(this), baseToken);
            // for multiplier

            // calculate base amount for openPosition -> spot price
            // maker openPosition -> spot price
            bool isRepegUp = repegParams.spotPrice > repegParams.oldMarkPrice;
            //internal swap
            IVPool(_vPool).internalSwap(
                IVPool.SwapParams({
                    trader: msg.sender,
                    baseToken: baseToken,
                    isBaseToQuote: !isRepegUp,
                    isExactInput: true,
                    isClose: false,
                    amount: type(uint256).max.div(1e10),
                    sqrtPriceLimitX96: repegParams.sqrtSpotPrice
                })
            );
            // calculate delta quote (1) -> new delta base (22)
            // calculate scale -> new mark price => rate = (% delta price)
            // calculate scale for long short = (diff delta base on (11 - 22)) / (total_long + total_short)
            // if delta base < 0 -> decrase delta long short
            // -> if long > short -> decrease long and increase short
            // -> if long < short -> increase long and decrease short
            // if delta base > 0 -> increase delta long short
            // -> if long > short -> increase long and decrease short
            // -> if long < short -> decrease long and increase short
            // update scale for position size for long short
            (repegParams.newSqrtMarkPrice, , , , , , ) = UniswapV3Broker.getSlot0(
                IMarketRegistry(_marketRegistry).getPool(baseToken)
            );
            repegParams.newMarkPrice = repegParams.newSqrtMarkPrice.formatSqrtPriceX96ToPriceX96().formatX96ToX10_18();
            // for multiplier
            GenericLogic.updateInfoMultiplier(
                address(this),
                baseToken,
                repegParams.oldLongPositionSize,
                repegParams.oldShortPositionSize,
                repegParams.oldDeltaQuote,
                repegParams.oldMarkPrice,
                repegParams.newMarkPrice,
                false
            );
            // for multiplier
            IVPool(_vPool).updateOverPriceSpreadTimestamp(baseToken);
            // emit event
            emit Repeg(baseToken, repegParams.oldMarkPrice, repegParams.newMarkPrice);
        }
    }
}

