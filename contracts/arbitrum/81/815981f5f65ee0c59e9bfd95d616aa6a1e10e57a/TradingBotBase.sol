// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./BoringOwnableUpgradeable.sol";
import "./TokenHelper.sol";
import "./ITradingBotBase.sol";
import "./IBotDecisionHelper.sol";
import "./SYBaseWithRewards.sol";
import "./TvlLib.sol";

contract TradingBotBase is SYBaseWithRewards, ITradingBotBase {
    using TokenAmountLib for TokenAmount[];
    using PYIndexLib for IPYieldToken;
    using MarketExtLib for MarketExtState;
    using Math for uint256;
    using Math for int256;

    IBotDecisionHelper public immutable decisionHelper;
    address public immutable market;
    address public immutable router;
    address public immutable SY;
    address public immutable PT;
    address public immutable YT;
    address public immutable PENDLE;

    TradingSpecs public specs;
    uint256 public buyBins;

    constructor(
        address _market,
        address _router,
        address _PENDLE,
        address _decisionHelper
    ) SYBaseWithRewards("Fortknox Vault", "Fortknox Vault", _getSYAddress(_market)) {
        (IStandardizedYield _SY, IPPrincipalToken _PT, IPYieldToken _YT) = IPMarket(_market)
            .readTokens();

        market = _market;
        router = _router;
        SY = address(_SY);
        PT = address(_PT);
        YT = address(_YT);
        PENDLE = _PENDLE;
        decisionHelper = IBotDecisionHelper(_decisionHelper);
    }

    function _getSYAddress(address _market) internal view returns (address) {
        (IStandardizedYield _SY, , ) = IPMarket(_market).readTokens();
        return address(_SY);
    }

    function approveInf(address token, address to) external onlyOwner {
        _safeApproveInf(token, to);
    }

    function compound(
        TokenInput calldata inp,
        uint256 minSyOut
    ) external onlyOwner returns (uint256 netSyOut) {
        netSyOut = _compoundSingle(inp, minSyOut);
        _transferOut(PENDLE, owner, _selfBalance(PENDLE));
        emit ClaimAndCompound(netSyOut);
    }

    function _readMarketExtState() internal view returns (MarketExtState memory marketExt) {
        marketExt.state = IPMarket(market).readState(router);
        marketExt.index = IPYieldToken(YT).newIndexView();
        marketExt.blockTime = block.timestamp;
    }

    function _readBotState() internal view returns (BotState memory botState) {
        botState.lpBalance = _selfBalance(market);
        botState.syBalance = _selfBalance(SY);
        botState.ytBalance = _selfBalance(YT);
        botState.ptBalance = _selfBalance(PT);
        botState.buyBins = buyBins;
    }

    function _setBuyBins(uint256 _buyBins) internal {
        buyBins = _buyBins;
    }

    function _compoundSingle(
        TokenInput memory inp,
        uint256 minSyOut
    ) internal returns (uint256 /*netSyOut*/) {
        if (inp.netTokenIn == type(uint256).max) inp.netTokenIn = _selfBalance(inp.tokenIn);

        return
            IPAllAction(router).mintSyFromToken{
                value: inp.tokenIn == NATIVE ? inp.netTokenIn : 0
            }(address(this), SY, minSyOut, inp);
    }

    function setSpecs(TradingSpecs calldata _specs) external onlyOwner {
        _setSpecs(_specs);
    }

    function _setSpecs(TradingSpecs memory _specs) internal {
        specs = _specs;
        _setBuyBins(specs.numOfBins);
    }

    function readStrategyData() public view returns (StrategyData memory strategyData) {
        strategyData.botState = _readBotState();
        strategyData.marketExt = _readMarketExtState();
        strategyData.specs = specs;
    }

    function _updateSellBinAfterTrade() internal {
        int256 binShift = IBotDecisionHelper(decisionHelper).getCurrentBin(readStrategyData());
        _setBuyBins((buyBins.Int() + binShift).Uint());
    }

    function getTvl(bool isLiquidateTvl) external view returns (uint256) {
        if (isLiquidateTvl) {
            return TvlLib.getLiquidateTvl(_readBotState(), _readMarketExtState());
        } else {
            return TvlLib.getOracleTvl(market, _readBotState());
        }
    }

    function getMaxAmountSharesToRedeem() external view returns (uint256) {
        uint256 liquidateTvl = TvlLib.getLiquidateTvl(_readBotState(), _readMarketExtState());
        return (_selfBalance(SY) * totalSupply()) / liquidateTvl;
    }

    /*///////////////////////////////////////////////////////////////
                               EIP-5115
    //////////////////////////////////////////////////////////////*/

    function _deposit(
        address,
        uint256 amountDeposited
    ) internal virtual override returns (uint256 amountSharesOut) {
        BotState memory botState = _readBotState();
        MarketExtState memory marketExt = _readMarketExtState();

        uint256 supply = totalSupply();
        if (supply == 0) return amountDeposited;

        uint256 tvl = Math.max(
            TvlLib.getOracleTvl(market, botState),
            TvlLib.getLiquidateTvl(botState, marketExt)
        );

        // Excluding the amount of SY already transferred in
        return (amountDeposited * totalSupply()) / (tvl - amountDeposited);
    }

    function _redeem(
        address receiver,
        address,
        uint256 amountSharesToRedeem
    ) internal virtual override returns (uint256 amountTokenOut) {
        uint256 tvlLiquidate = TvlLib.getLiquidateTvl(_readBotState(), _readMarketExtState());

        // including the amount of shares already burned when this function is called
        amountTokenOut =
            (tvlLiquidate * amountSharesToRedeem) /
            (totalSupply() + amountSharesToRedeem);
        _transferOut(SY, receiver, amountTokenOut);
    }

    function _previewDeposit(
        address,
        uint256 amountTokenToDeposit
    ) internal view override returns (uint256 amountSharesOut) {
        uint256 supply = totalSupply();
        if (supply == 0) return amountTokenToDeposit;

        BotState memory botState = _readBotState();
        MarketExtState memory marketExt = _readMarketExtState();

        uint256 tvl = Math.max(
            TvlLib.getOracleTvl(market, botState),
            TvlLib.getLiquidateTvl(botState, marketExt)
        );
        return (amountTokenToDeposit * supply) / tvl;
    }

    function _previewRedeem(
        address,
        uint256 amountSharesToRedeem
    ) internal view override returns (uint256 amountTokenOut) {
        uint256 tvlLiquidate = TvlLib.getLiquidateTvl(_readBotState(), _readMarketExtState());
        return (tvlLiquidate * amountSharesToRedeem) / totalSupply();
    }

    function exchangeRate() public view virtual override returns (uint256) {
        return TvlLib.getOracleTvl(market, _readBotState()).divDown(totalSupply());
    }

    function _redeemExternalReward() internal override {
        IPYieldToken(YT).redeemDueInterestAndRewards(address(this), true, true);
        IPMarket(market).redeemRewards(address(this));
        IStandardizedYield(SY).claimRewards(address(this));
    }

    function _getRewardTokens() internal view virtual override returns (address[] memory res) {
        res = new address[](1);
        res[0] = PENDLE;
    }

    function getTokensIn() public view virtual override returns (address[] memory res) {
        res = new address[](1);
        res[0] = SY;
    }

    function getTokensOut() public view virtual override returns (address[] memory res) {
        res = new address[](1);
        res[0] = SY;
    }

    function isValidTokenIn(address token) public view virtual override returns (bool) {
        return token == SY;
    }

    function isValidTokenOut(address token) public view virtual override returns (bool) {
        return token == SY;
    }

    function assetInfo()
        external
        view
        returns (AssetType assetType, address assetAddress, uint8 assetDecimals)
    {
        return (AssetType.TOKEN, SY, IERC20Metadata(SY).decimals());
    }

    /**
     * ERC20 overrides
     */
    function name()
        public
        view
        virtual
        override(PendleERC20, IERC20Metadata)
        returns (string memory)
    {
        return "Fortknox Vault";
    }

    function symbol()
        public
        view
        virtual
        override(PendleERC20, IERC20Metadata)
        returns (string memory)
    {
        return "Fortknox Vault";
    }
}

