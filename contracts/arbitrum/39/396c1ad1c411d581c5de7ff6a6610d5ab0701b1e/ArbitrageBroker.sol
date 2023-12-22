// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import {IArbitrageBroker, ICollateral, ILongShortToken, IPrePOMarket, ISwapRouter} from "./IArbitrageBroker.sol";
import {IAccountList, AccountListCaller} from "./AccountListCaller.sol";
import {SafeAccessControlEnumerable} from "./SafeAccessControlEnumerable.sol";
import {WithdrawERC20} from "./WithdrawERC20.sol";

contract ArbitrageBroker is
  IArbitrageBroker,
  AccountListCaller,
  SafeAccessControlEnumerable,
  WithdrawERC20
{
  ICollateral private immutable _collateral;
  ISwapRouter private immutable _swapRouter;

  uint24 public constant override POOL_FEE_TIER = 10000;
  bytes32 public constant override BUY_AND_REDEEM_ROLE =
    keccak256("buyAndRedeem");
  bytes32 public constant override MINT_AND_SELL_ROLE =
    keccak256("mintAndSell");
  bytes32 public constant override SET_ACCOUNT_LIST_ROLE =
    keccak256("setAccountList");
  bytes32 public constant override WITHDRAW_ERC20_ROLE =
    keccak256("withdrawERC20");

  constructor(ICollateral collateral, ISwapRouter swapRouter) {
    _collateral = collateral;
    _swapRouter = swapRouter;
    collateral.approve(address(swapRouter), type(uint256).max);
    _grantRole(BUY_AND_REDEEM_ROLE, msg.sender);
    _grantRole(MINT_AND_SELL_ROLE, msg.sender);
    _grantRole(SET_ACCOUNT_LIST_ROLE, msg.sender);
    _grantRole(WITHDRAW_ERC20_ROLE, msg.sender);
  }

  modifier onlyValidMarkets(IPrePOMarket market) {
    address marketAddress = address(market);
    address swapRouterAddress = address(_swapRouter);
    address arbitrageBrokerAddress = address(this);
    if (!_accountList.isIncluded(marketAddress))
      revert InvalidMarket(marketAddress);
    ILongShortToken longToken = IPrePOMarket(market).getLongToken();
    ILongShortToken shortToken = IPrePOMarket(market).getShortToken();
    if (
      _collateral.allowance(arbitrageBrokerAddress, marketAddress) !=
      type(uint256).max
    ) _collateral.approve(marketAddress, type(uint256).max);
    if (
      longToken.allowance(arbitrageBrokerAddress, swapRouterAddress) !=
      type(uint256).max
    ) longToken.approve(swapRouterAddress, type(uint256).max);
    if (
      shortToken.allowance(arbitrageBrokerAddress, swapRouterAddress) !=
      type(uint256).max
    ) shortToken.approve(swapRouterAddress, type(uint256).max);
    _;
  }

  function buyAndRedeem(
    IPrePOMarket market,
    OffChainTradeParams calldata tradeParams
  )
    external
    override
    onlyRole(BUY_AND_REDEEM_ROLE)
    onlyValidMarkets(market)
    returns (
      uint256 profit,
      uint256 collateralToBuyLong,
      uint256 collateralToBuyShort
    )
  {
    uint256 collateralBefore = _collateral.balanceOf(address(this));
    collateralToBuyLong = _buyLongOrShort(
      tradeParams,
      market.getLongToken(),
      true
    );
    collateralToBuyShort = _buyLongOrShort(
      tradeParams,
      market.getShortToken(),
      false
    );
    market.redeem(
      tradeParams.longShortAmount,
      tradeParams.longShortAmount,
      address(this),
      bytes("")
    );
    uint256 collateralAfter = _collateral.balanceOf(address(this));
    if (collateralBefore >= collateralAfter) {
      revert UnprofitableTrade(collateralBefore, collateralAfter);
    }
    profit = collateralAfter - collateralBefore;
    emit ArbitrageProfit(address(market), false, profit);
  }

  function mintAndSell(
    IPrePOMarket market,
    OffChainTradeParams calldata tradeParams
  )
    external
    override
    onlyRole(MINT_AND_SELL_ROLE)
    onlyValidMarkets(market)
    returns (
      uint256 profit,
      uint256 collateralFromSellingLong,
      uint256 collateralFromSellingShort
    )
  {
    uint256 collateralBefore = _collateral.balanceOf(address(this));
    market.mint(tradeParams.longShortAmount, address(this), bytes(""));
    collateralFromSellingLong = _sellLongOrShort(
      tradeParams,
      market.getLongToken(),
      true
    );
    collateralFromSellingShort = _sellLongOrShort(
      tradeParams,
      market.getShortToken(),
      false
    );
    uint256 collateralAfter = _collateral.balanceOf(address(this));
    if (collateralBefore >= collateralAfter) {
      revert UnprofitableTrade(collateralBefore, collateralAfter);
    }
    profit = collateralAfter - collateralBefore;
    emit ArbitrageProfit(address(market), true, profit);
  }

  function getCollateral() external view override returns (ICollateral) {
    return _collateral;
  }

  function getSwapRouter() external view override returns (ISwapRouter) {
    return _swapRouter;
  }

  function _buyLongOrShort(
    OffChainTradeParams calldata tradeParams,
    ILongShortToken longShortToken,
    bool long
  ) private returns (uint256) {
    uint256 amountInMaximum = long
      ? tradeParams.collateralLimitForLong
      : tradeParams.collateralLimitForShort;
    ISwapRouter.ExactOutputSingleParams memory exactOutputSingleParams = ISwapRouter
      .ExactOutputSingleParams(
        address(_collateral), // tokenIn
        address(longShortToken), // tokenOut
        POOL_FEE_TIER,
        address(this), // recipient
        tradeParams.deadline,
        tradeParams.longShortAmount, // amountOut
        amountInMaximum,
        0 // sqrtPriceLimitX96
      );
    return _swapRouter.exactOutputSingle(exactOutputSingleParams);
  }

  function _sellLongOrShort(
    OffChainTradeParams calldata tradeParams,
    ILongShortToken longShortToken,
    bool long
  ) private returns (uint256) {
    uint256 amountOutMinimum = long
      ? tradeParams.collateralLimitForLong
      : tradeParams.collateralLimitForShort;
    ISwapRouter.ExactInputSingleParams memory exactInputSingleParams = ISwapRouter
      .ExactInputSingleParams(
        address(longShortToken), // tokenIn
        address(_collateral), // tokenOut
        POOL_FEE_TIER,
        address(this), // recipient
        tradeParams.deadline,
        tradeParams.longShortAmount, // amountIn
        amountOutMinimum,
        0 // sqrtPriceLimitX96
      );
    return _swapRouter.exactInputSingle(exactInputSingleParams);
  }

  function setAccountList(IAccountList accountList)
    public
    virtual
    override
    onlyRole(SET_ACCOUNT_LIST_ROLE)
  {
    super.setAccountList(accountList);
  }

  function withdrawERC20(
    address[] calldata erc20Tokens,
    uint256[] calldata amounts
  ) public override onlyRole(WITHDRAW_ERC20_ROLE) {
    super.withdrawERC20(erc20Tokens, amounts);
  }

  function withdrawERC20(address[] calldata erc20Tokens)
    public
    override
    onlyRole(WITHDRAW_ERC20_ROLE)
  {
    super.withdrawERC20(erc20Tokens);
  }
}

