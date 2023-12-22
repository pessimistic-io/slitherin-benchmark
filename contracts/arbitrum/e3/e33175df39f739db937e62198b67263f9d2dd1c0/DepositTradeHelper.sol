// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import "./IDepositTradeHelper.sol";
import "./SafeOwnable.sol";
import "./ReentrancyGuard.sol";
import "./draft-IERC20Permit.sol";

contract DepositTradeHelper is
  IDepositTradeHelper,
  ReentrancyGuard,
  SafeOwnable
{
  ICollateral private immutable _collateral;
  IERC20 private immutable _baseToken;
  ISwapRouter private immutable _swapRouter;
  IVault private immutable _wstethVault;
  bytes32 private _wstethPoolId;

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
    OffChainBalancerParams calldata balancerParams
  ) public payable override nonReentrant returns (uint256) {
    _wrapAndDeposit(recipient, balancerParams);
  }

  function depositAndTrade(
    uint256 baseTokenAmount,
    Permit calldata baseTokenPermit,
    Permit calldata collateralPermit,
    OffChainTradeParams calldata tradeParams
  ) external override nonReentrant {
    if (baseTokenPermit.deadline != 0) {
      IERC20Permit(address(_baseToken)).permit(
        msg.sender,
        address(this),
        type(uint256).max,
        baseTokenPermit.deadline,
        baseTokenPermit.v,
        baseTokenPermit.r,
        baseTokenPermit.s
      );
    }
    _baseToken.transferFrom(msg.sender, address(this), baseTokenAmount);
    if (collateralPermit.deadline != 0) {
      _collateral.permit(
        msg.sender,
        address(this),
        type(uint256).max,
        collateralPermit.deadline,
        collateralPermit.v,
        collateralPermit.r,
        collateralPermit.s
      );
    }
    uint256 _collateralAmountMinted = _collateral.deposit(
      msg.sender,
      baseTokenAmount
    );
    _collateral.transferFrom(
      msg.sender,
      address(this),
      _collateralAmountMinted
    );
    ISwapRouter.ExactInputSingleParams
      memory exactInputSingleParams = ISwapRouter.ExactInputSingleParams(
        address(_collateral),
        tradeParams.tokenOut,
        POOL_FEE_TIER,
        msg.sender,
        tradeParams.deadline,
        _collateralAmountMinted,
        tradeParams.amountOutMinimum,
        tradeParams.sqrtPriceLimitX96
      );
    _swapRouter.exactInputSingle(exactInputSingleParams);
  }

  function wrapAndDepositAndTrade(
    Permit calldata collateralPermit,
    OffChainTradeParams calldata tradeParams
  ) external payable override nonReentrant {}

  function withdrawAndUnwrap(
    address recipient,
    uint256 amount,
    Permit calldata collateralPermit,
    OffChainBalancerParams calldata balancerParams
  ) external override nonReentrant {
    uint256 recipientETHBefore = recipient.balance;
    if (collateralPermit.deadline != 0) {
      _collateral.permit(
        msg.sender,
        address(this),
        type(uint256).max,
        collateralPermit.deadline,
        collateralPermit.v,
        collateralPermit.r,
        collateralPermit.s
      );
    }
    _collateral.transferFrom(msg.sender, address(this), amount);
    uint256 wstethAmount = _collateral.withdraw(address(this), amount);
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
    _collateral.deposit(recipient, wstethAmount);
  }
}

