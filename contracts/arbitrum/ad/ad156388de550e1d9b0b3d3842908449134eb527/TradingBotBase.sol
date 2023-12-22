// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./BoringOwnableUpgradeable.sol";
import "./TokenHelper.sol";
import "./ITradingBotBase.sol";

import "./BotSimulationLib.sol";

abstract contract TradingBotBase is BoringOwnableUpgradeable, TokenHelper, ITradingBotBase {
    using TokenAmountLib for TokenAmount[];
    using PYIndexLib for IPYieldToken;

    address public immutable market;
    address public immutable router;
    address public immutable SY;
    address public immutable PT;
    address public immutable YT;
    address public immutable PENDLE;

    uint256 public buyBins;

    constructor(address _market, address _router, address _PENDLE) initializer {
        (IStandardizedYield _SY, IPPrincipalToken _PT, IPYieldToken _YT) = IPMarket(_market)
            .readTokens();

        market = _market;
        router = _router;
        SY = address(_SY);
        PT = address(_PT);
        YT = address(_YT);
        PENDLE = _PENDLE;

        __BoringOwnable_init();
    }

    function approveInf(MultiApproval[] calldata arr) external onlyOwner {
        for (uint256 i = 0; i < arr.length; ) {
            MultiApproval calldata ele = arr[i];
            for (uint256 j = 0; j < ele.tokens.length; ) {
                _safeApproveInf(ele.tokens[j], ele.spender);
                unchecked {
                    j++;
                }
            }
            unchecked {
                i++;
            }
        }
    }

    function depositSy(uint256 netSyIn) external onlyOwner {
        _transferIn(SY, msg.sender, netSyIn);
        emit DepositSy(netSyIn);
    }

    /// @dev Receives token and compound to SY
    function depositToken(
        TokenInput calldata inp,
        uint256 minSyOut
    ) external payable onlyOwner {
        _transferIn(inp.tokenIn, msg.sender, inp.netTokenIn);
        _compoundSingle(inp, minSyOut);
        emit DepositToken(inp.tokenIn, inp.netTokenIn);
    }

    function withdrawFunds(address token, uint256 amount) external onlyOwner {
        if (amount == type(uint256).max) amount = _selfBalance(token);
        _transferOut(token, msg.sender, amount);
        emit WithdrawFunds(token, amount);
    }

    function claimAndCompound(
        TokenInput[] calldata inps,
        uint256 minSyOut
    ) external onlyOwner returns (uint256 netSyOut, uint256 netPendleOut) {
        _claimRewards();

        netSyOut = _compound(inps, minSyOut);

        netPendleOut = _selfBalance(PENDLE);
        _transferOut(PENDLE, owner, netPendleOut);
        emit ClaimAndCompound(netSyOut, netPendleOut);
    }

    /// Claim without compound, intended for offchain usage
    /// @dev SY interest from YT is excluded
    function claimWithoutCompound() external onlyOwner returns (TokenAmount[] memory rewards) {
        address[] memory ytRewardTokens = IPYieldToken(YT).getRewardTokens();
        (, uint256[] memory ytRewardAmounts) = IPYieldToken(YT).redeemDueInterestAndRewards(
            address(this),
            true,
            true
        );
        rewards = rewards.add(ytRewardTokens, ytRewardAmounts);

        address[] memory syRewardTokens = IStandardizedYield(SY).getRewardTokens();
        uint256[] memory syRewardAmounts = IStandardizedYield(SY).claimRewards(address(this));
        rewards = rewards.add(syRewardTokens, syRewardAmounts);

        address[] memory lpRewardTokens = IPMarket(market).getRewardTokens();
        uint256[] memory lpRewardAmounts = IPMarket(market).redeemRewards(address(this));
        rewards = rewards.add(lpRewardTokens, lpRewardAmounts);
    }

    function readMarketExtState() public returns (MarketExtState memory marketExt) {
        marketExt.state = IPMarket(market).readState(router);
        marketExt.index = IPYieldToken(YT).newIndex();
        marketExt.blockTime = block.timestamp;
    }

    function readBotState() public view returns (BotState memory botState) {
        botState.lpBalance = _selfBalance(market);
        botState.syBalance = _selfBalance(SY);
        botState.ytBalance = _selfBalance(YT);
        botState.buyBins = buyBins;
    }

    receive() external payable {}

    function _setBuyBins(uint256 _buyBins) internal {
        buyBins = _buyBins;
    }

    function _claimRewards() internal {
        IPYieldToken(YT).redeemDueInterestAndRewards(address(this), true, true);
        IStandardizedYield(SY).claimRewards(address(this));
        IPMarket(market).redeemRewards(address(this));
    }

    function _compound(
        TokenInput[] calldata inps,
        uint256 minSyOut
    ) internal returns (uint256 netSyOut) {
        netSyOut = 0;

        for (uint256 i = 0; i < inps.length; ++i) {
            netSyOut += _compoundSingle(inps[i], 0);
        }

        if (netSyOut < minSyOut) revert Errors.BotInsufficientSyOut(netSyOut, minSyOut);
        return netSyOut;
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
}

