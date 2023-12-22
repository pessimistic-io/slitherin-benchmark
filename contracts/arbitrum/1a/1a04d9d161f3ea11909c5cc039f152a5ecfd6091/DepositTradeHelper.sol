// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import {IAsset, ICollateral, IDepositTradeHelper, IERC20, ISwapRouter, IVault} from "./IDepositTradeHelper.sol";
import {SafeOwnable} from "./SafeOwnable.sol";
import {ITokenSender, TokenSenderCaller} from "./TokenSenderCaller.sol";
import {TreasuryCaller} from "./TreasuryCaller.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {IERC20Permit} from "./draft-IERC20Permit.sol";

contract DepositTradeHelper is
  IDepositTradeHelper,
  ReentrancyGuard,
  SafeOwnable,
  TokenSenderCaller,
  TreasuryCaller
{
  ICollateral private immutable _collateral;
  IERC20 private immutable _baseToken;
  ISwapRouter private immutable _swapRouter;
  IVault private immutable _wstethVault;

  bytes32 private _wstethPoolId;
  uint256 private _tradeFeePercent;

  uint24 public constant override POOL_FEE_TIER = 10000;

  constructor(
    ICollateral collateral,
    ISwapRouter swapRouter,
    IVault wstethVault
  ) {
    _collateral = collateral;
    _baseToken = collateral.getBaseToken();
    _swapRouter = swapRouter;
    _wstethVault = wstethVault;
    collateral.getBaseToken().approve(address(collateral), type(uint256).max);
    collateral.getBaseToken().approve(address(wstethVault), type(uint256).max);
    collateral.approve(address(swapRouter), type(uint256).max);
  }

  /// @dev Assumes `_baseToken` is WstETH
  function wrapAndDeposit(
    address recipient,
    bytes calldata depositData,
    OffChainBalancerParams calldata balancerParams
  ) external payable override nonReentrant {
    _wrapAndDeposit(recipient, depositData, balancerParams);
  }

  function wrapAndDeposit(
    address recipient,
    OffChainBalancerParams calldata balancerParams
  ) external payable override nonReentrant {
    _wrapAndDeposit(recipient, balancerParams);
  }

  function tradeForPosition(
    address recipient,
    uint256 collateralAmount,
    Permit calldata collateralPermit,
    OffChainTradeParams calldata tradeParams
  ) external override nonReentrant {
    _permitAndTransfer(
      msg.sender,
      address(_collateral),
      collateralAmount,
      collateralPermit
    );
    uint256 collateralAmountAfterFee = _sendCollateralFeeAndRebate(
      recipient,
      collateralAmount
    );
    _trade(
      recipient,
      address(_collateral),
      tradeParams.positionToken,
      collateralAmountAfterFee,
      tradeParams
    );
  }

  function tradeForCollateral(
    address recipient,
    uint256 positionAmount,
    Permit calldata positionPermit,
    OffChainTradeParams calldata tradeParams
  ) external override nonReentrant {
    _permitAndTransfer(
      msg.sender,
      tradeParams.positionToken,
      positionAmount,
      positionPermit
    );
    /**
     * Since any position token could be passed in, it is simpler to just
     * perform a one-time approval on the first trade of a Long or Short
     * token. This removes the need to "register" Long or Short tokens
     * every time we need the contract to support one.
     */
    if (
      IERC20(tradeParams.positionToken).allowance(
        address(this),
        address(_swapRouter)
      ) != type(uint256).max
    ) {
      IERC20(tradeParams.positionToken).approve(
        address(_swapRouter),
        type(uint256).max
      );
    }
    // trade recipient is this contract so fee can be captured
    uint256 collateralAmountBeforeFee = _trade(
      address(this),
      tradeParams.positionToken,
      address(_collateral),
      positionAmount,
      tradeParams
    );
    uint256 collateralAmountAfterFee = _sendCollateralFeeAndRebate(
      recipient,
      collateralAmountBeforeFee
    );
    _collateral.transfer(recipient, collateralAmountAfterFee);
  }

  function wrapAndDepositAndTrade(
    address recipient,
    bytes calldata depositData,
    OffChainBalancerParams calldata balancerParams,
    Permit calldata collateralPermit,
    OffChainTradeParams calldata tradeParams
  ) external payable override nonReentrant {
    uint256 collateralAmountBeforeFee = _wrapAndDeposit(
      recipient,
      depositData,
      balancerParams
    );
    /**
     * funder = recipient in this case since minted collateral is attributed
     * to the recipient. Since this function will only be used for collateral
     * => position trading, can assume collateral will be the input token and
     * position token as the output.
     */
    _permitAndTransfer(
      recipient,
      address(_collateral),
      collateralAmountBeforeFee,
      collateralPermit
    );
    uint256 collateralAmountAfterFee = _sendCollateralFeeAndRebate(
      recipient,
      collateralAmountBeforeFee
    );
    _trade(
      recipient,
      address(_collateral),
      tradeParams.positionToken,
      collateralAmountAfterFee,
      tradeParams
    );
  }

  function wrapAndDepositAndTrade(
    address recipient,
    OffChainBalancerParams calldata balancerParams,
    Permit calldata collateralPermit,
    OffChainTradeParams calldata tradeParams
  ) external payable override nonReentrant {
    uint256 collateralAmountBeforeFee = _wrapAndDeposit(
      recipient,
      balancerParams
    );
    /**
     * funder = recipient in this case since minted collateral is attributed
     * to the recipient. Since this function will only be used for collateral
     * => position trading, can assume collateral will be the input token and
     * position token as the output.
     */
    _permitAndTransfer(
      recipient,
      address(_collateral),
      collateralAmountBeforeFee,
      collateralPermit
    );
    uint256 collateralAmountAfterFee = _sendCollateralFeeAndRebate(
      recipient,
      collateralAmountBeforeFee
    );
    _trade(
      recipient,
      address(_collateral),
      tradeParams.positionToken,
      collateralAmountAfterFee,
      tradeParams
    );
  }

  function withdrawAndUnwrap(
    address recipient,
    uint256 amount,
    bytes calldata withdrawData,
    Permit calldata collateralPermit,
    OffChainBalancerParams calldata balancerParams
  ) external override nonReentrant {
    uint256 recipientETHBefore = recipient.balance;
    _permitAndTransfer(
      msg.sender,
      address(_collateral),
      amount,
      collateralPermit
    );
    uint256 wstethAmount = _collateral.withdraw(
      address(this),
      amount,
      withdrawData
    );
    IERC20 rewardToken = _tokenSender.getOutputToken();
    uint256 rewardTokenBalance = rewardToken.balanceOf(address(this));
    if (rewardTokenBalance > 0)
      rewardToken.transfer(recipient, rewardTokenBalance);
    IVault.SingleSwap memory wstethSwapParams = IVault.SingleSwap(
      _wstethPoolId,
      IVault.SwapKind.GIVEN_IN,
      IAsset(address(_baseToken)),
      // output token as zero address means ETH
      IAsset(address(0)),
      wstethAmount,
      ""
    );
    IVault.FundManagement memory wstethFundingParams = IVault.FundManagement(
      address(this),
      false,
      // Unwraps WETH into ETH directly to recipient
      payable(recipient),
      false
    );
    _wstethVault.swap(
      wstethSwapParams,
      wstethFundingParams,
      balancerParams.amountOutMinimum,
      balancerParams.deadline
    );
    require(
      recipient.balance - recipientETHBefore >=
        balancerParams.amountOutMinimum,
      "Insufficient ETH from swap"
    );
  }

  function withdrawAndUnwrap(
    address recipient,
    uint256 amount,
    Permit calldata collateralPermit,
    OffChainBalancerParams calldata balancerParams
  ) external override nonReentrant {
    uint256 recipientETHBefore = recipient.balance;
    _permitAndTransfer(
      msg.sender,
      address(_collateral),
      amount,
      collateralPermit
    );
    uint256 wstethAmount = _collateral.withdraw(address(this), amount);
    IERC20 rewardToken = _tokenSender.getOutputToken();
    uint256 rewardTokenBalance = rewardToken.balanceOf(address(this));
    if (rewardTokenBalance > 0)
      rewardToken.transfer(recipient, rewardTokenBalance);
    IVault.SingleSwap memory wstethSwapParams = IVault.SingleSwap(
      _wstethPoolId,
      IVault.SwapKind.GIVEN_IN,
      IAsset(address(_baseToken)),
      // output token as zero address means ETH
      IAsset(address(0)),
      wstethAmount,
      ""
    );
    IVault.FundManagement memory wstethFundingParams = IVault.FundManagement(
      address(this),
      false,
      // Unwraps WETH into ETH directly to recipient
      payable(recipient),
      false
    );
    _wstethVault.swap(
      wstethSwapParams,
      wstethFundingParams,
      balancerParams.amountOutMinimum,
      balancerParams.deadline
    );
    require(
      recipient.balance - recipientETHBefore >=
        balancerParams.amountOutMinimum,
      "Insufficient ETH from swap"
    );
  }

  function setWstethPoolId(bytes32 wstethPoolId) external override onlyOwner {
    _wstethPoolId = wstethPoolId;
    emit WstethPoolIdChange(wstethPoolId);
  }

  function setTradeFeePercent(uint256 tradeFeePercent)
    external
    override
    onlyOwner
  {
    _tradeFeePercent = tradeFeePercent;
    emit TradeFeePercentChange(tradeFeePercent);
  }

  function setAmountMultiplier(address account, uint256 amountMultiplier)
    public
    override
    onlyOwner
  {
    /**
     * Zero address is used here to represent that this multiplier will be
     * applied to all accounts.
     */
    if (account != address(0)) revert InvalidAccount();
    super.setAmountMultiplier(account, amountMultiplier);
  }

  function setTokenSender(ITokenSender tokenSender) public override onlyOwner {
    super.setTokenSender(tokenSender);
  }

  function setTreasury(address treasury) public override onlyOwner {
    super.setTreasury(treasury);
  }

  function getCollateral() external view override returns (ICollateral) {
    return _collateral;
  }

  function getBaseToken() external view override returns (IERC20) {
    return _baseToken;
  }

  function getSwapRouter() external view override returns (ISwapRouter) {
    return _swapRouter;
  }

  function getWstethVault() external view override returns (IVault) {
    return _wstethVault;
  }

  function getWstethPoolId() external view override returns (bytes32) {
    return _wstethPoolId;
  }

  function getTradeFeePercent() external view override returns (uint256) {
    return _tradeFeePercent;
  }

  function _wrapAndDeposit(
    address recipient,
    bytes memory depositData,
    OffChainBalancerParams calldata balancerParams
  ) internal returns (uint256) {
    uint256 wstethBalanceBefore = _baseToken.balanceOf(address(this));
    IVault.SingleSwap memory wstethSwapParams = IVault.SingleSwap(
      _wstethPoolId,
      IVault.SwapKind.GIVEN_IN,
      // input token as zero address means ETH
      IAsset(address(0)),
      IAsset(address(_baseToken)),
      msg.value,
      // keep optional `userData` field empty
      ""
    );
    IVault.FundManagement memory wstethFundingParams = IVault.FundManagement(
      address(this),
      // false because we are not trading with internal pool balances
      false,
      /**
       * Although the contract is not receiving ETH in this swap, the
       * parameter is payable because Balancer allows recipients to receive
       * ETH.
       */
      payable(address(this)),
      false
    );
    uint256 wstethAmount = _wstethVault.swap{value: msg.value}(
      wstethSwapParams,
      wstethFundingParams,
      balancerParams.amountOutMinimum,
      balancerParams.deadline
    );
    require(
      _baseToken.balanceOf(address(this)) - wstethBalanceBefore >=
        balancerParams.amountOutMinimum,
      "Insufficient wstETH from swap"
    );
    return _collateral.deposit(recipient, wstethAmount, depositData);
  }

  function _wrapAndDeposit(
    address recipient,
    OffChainBalancerParams calldata balancerParams
  ) internal returns (uint256) {
    uint256 wstethBalanceBefore = _baseToken.balanceOf(address(this));
    IVault.SingleSwap memory wstethSwapParams = IVault.SingleSwap(
      _wstethPoolId,
      IVault.SwapKind.GIVEN_IN,
      // input token as zero address means ETH
      IAsset(address(0)),
      IAsset(address(_baseToken)),
      msg.value,
      // keep optional `userData` field empty
      ""
    );
    IVault.FundManagement memory wstethFundingParams = IVault.FundManagement(
      address(this),
      // false because we are not trading with internal pool balances
      false,
      /**
       * Although the contract is not receiving ETH in this swap, the
       * parameter is payable because Balancer allows recipients to receive
       * ETH.
       */
      payable(address(this)),
      false
    );
    uint256 wstethAmount = _wstethVault.swap{value: msg.value}(
      wstethSwapParams,
      wstethFundingParams,
      balancerParams.amountOutMinimum,
      balancerParams.deadline
    );
    require(
      _baseToken.balanceOf(address(this)) - wstethBalanceBefore >=
        balancerParams.amountOutMinimum,
      "Insufficient wstETH from swap"
    );
    return _collateral.deposit(recipient, wstethAmount);
  }

  function _permitAndTransfer(
    address funder,
    address token,
    uint256 amount,
    Permit calldata permit
  ) internal {
    /**
     * Because `IERC20Permit` and `IERC20` do not overlap, it is cleaner to
     * pass it in as an address and recast it separately when we need to
     * access its functions.
     */
    if (permit.deadline != 0) {
      IERC20Permit(token).permit(
        funder,
        address(this),
        type(uint256).max,
        permit.deadline,
        permit.v,
        permit.r,
        permit.s
      );
    }
    IERC20(token).transferFrom(funder, address(this), amount);
  }

  function _sendCollateralFeeAndRebate(
    address recipient,
    uint256 amountBeforeFee
  ) internal returns (uint256 amountAfterFee) {
    uint256 fee = (amountBeforeFee * _tradeFeePercent) / PERCENT_UNIT;
    amountAfterFee = amountBeforeFee - fee;
    if (fee == 0) return amountAfterFee;
    _collateral.transfer(_treasury, fee);
    if (address(_tokenSender) == address(0)) return amountAfterFee;
    uint256 scaledFee = (fee * _accountToAmountMultiplier[address(0)]) /
      PERCENT_UNIT;
    if (scaledFee == 0) return amountAfterFee;
    _tokenSender.send(recipient, scaledFee);
  }

  function _trade(
    address recipient,
    address inputToken,
    address outputToken,
    uint256 inputTokenAmount,
    OffChainTradeParams calldata tradeParams
  ) internal returns (uint256 outputTokenAmount) {
    ISwapRouter.ExactInputSingleParams memory exactInputSingleParams = ISwapRouter
      .ExactInputSingleParams(
        inputToken,
        /**
         * Don't use tradeParams.positionToken because calling function might
         * have position token as the input rather than the output.
         */
        outputToken,
        POOL_FEE_TIER,
        recipient,
        tradeParams.deadline,
        inputTokenAmount,
        tradeParams.amountOutMinimum,
        tradeParams.sqrtPriceLimitX96
      );
    outputTokenAmount = _swapRouter.exactInputSingle(exactInputSingleParams);
  }
}

