// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8;

import "./ERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./Initializable.sol";

import "./SafeERC20.sol";
import "./IERC20.sol";

import "./IOldPlatformMinimal.sol";
import "./IOldThetaVaultMinimal.sol";
import "./IRequestManager.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Pair.sol";
import "./IUniswapV2Factory.sol";

contract DisabledThetaVault is
  Initializable,
  IOldThetaVaultMinimal,
  IRequestManager,
  OwnableUpgradeable,
  ERC20Upgradeable,
  ReentrancyGuardUpgradeable
{
  using SafeERC20 for IERC20;

  struct Request {
    uint8 requestType; // 1 => deposit, 2 => withdraw
    uint168 tokenAmount;
    uint32 targetTimestamp;
    address owner;
    bool shouldStake;
  }

  uint8 private constant DEPOSIT_REQUEST_TYPE = 1;
  uint8 private constant WITHDRAW_REQUEST_TYPE = 2;

  uint256 internal constant PRECISION_DECIMALS = 18;
  uint16 internal constant MAX_PERCENTAGE = 10000;

  uint16 public constant UNISWAP_REMOVE_MAX_FEE_PERCENTAGE = 5;

  address public fulfiller;

  IERC20 internal token;
  IOldPlatformMinimal internal platform;
  IOldVolTokenMinimal public override volToken;
  IUniswapV2Router02 public router;

  uint256 public override nextRequestId;
  mapping(uint256 => Request) public override requests;
  mapping(address => uint256) public lastDepositTimestamp;

  uint256 public initialTokenToThetaTokenRate;

  uint256 public totalDepositRequestsAmount;
  uint256 public totalVaultLeveragedAmount; // Obsolete

  uint16 public minPoolSkewPercentage;
  uint16 public extraLiquidityPercentage;
  uint256 public depositCap;
  uint256 public requestDelay;
  uint256 public lockupPeriod;
  uint256 public liquidationPeriod;

  uint256 public override minRequestId;
  uint256 public override maxMinRequestIncrements;
  uint256 public minDepositAmount;
  uint256 public minWithdrawAmount;

  uint256 public totalHoldingsAmount;
  uint16 public depositHoldingsPercentage;

  uint16 public minDexPercentageAllowed;

  IRewardRouter public rewardRouter;
  bool public isDisabled;

  function initialize() public onlyInitializing {}

  function disable() external onlyOwner {
    require(!isDisabled, 'Theta vault is already disabled');

    // remove liquidity
    IERC20Upgradeable poolPair = IERC20Upgradeable(address(getPair()));
    router.removeLiquidity(
      address(volToken),
      address(token),
      poolPair.balanceOf(address(this)),
      0,
      0,
      address(this),
      block.timestamp
    );
    uint256 toBurn = IERC20Upgradeable(address(volToken)).balanceOf(address(this));
    burnVolTokens(toBurn);

    // withdraw platform liquidity
    uint256 lpTokenToWithdraw = IERC20Upgradeable(address(platform)).balanceOf(address(this));
    platform.withdrawLPTokens(lpTokenToWithdraw);

    isDisabled = true;
  }

  function exit() public nonReentrant {
    uint256 amountToWithdraw = IERC20Upgradeable(address(this)).balanceOf(msg.sender);
    submitWithdrawRequest(uint168(amountToWithdraw));
  }

  function submitDepositRequest(uint168 _tokenAmount) external override returns (uint256 requestId) {
    revert('Disabled');
  }

  function submitWithdrawRequest(uint168 _thetaTokenAmount) public override returns (uint256 requestId) {
    require(isDisabled, 'Theta vault must be disabled');

    _burn(msg.sender, _thetaTokenAmount);

    uint256 tokensToSend = (_thetaTokenAmount * token.balanceOf(address(this))) / totalSupply();
    token.safeTransfer(msg.sender, tokensToSend);

    requestId = nextRequestId;
    nextRequestId += 1; // Overflow allowed to keep id cycling
    emit SubmitRequest(
      requestId,
      WITHDRAW_REQUEST_TYPE,
      _thetaTokenAmount,
      uint32(block.timestamp),
      msg.sender,
      token.balanceOf(address(this)),
      totalSupply()
    );
    emit FulfillWithdraw(requestId, msg.sender, tokensToSend, 0, 0, 0, 0, _thetaTokenAmount);
  }

  function fulfillDepositRequest(uint256 _requestId) external override returns (uint256 thetaTokensMinted) {
    revert('Disabled');
  }

  function fulfillWithdrawRequest(uint256 _requestId) external override returns (uint256 tokenWithdrawnAmount) {
    revert('Disabled');
  }

  function liquidateRequest(uint256 _requestId) external override nonReentrant {
    Request memory request = requests[_requestId];
    require(request.requestType != 0); // 'Request id not found'
    require(isLiquidable(_requestId), 'Not liquidable');

    _liquidateRequest(_requestId);
  }

  function rebalance() external override onlyOwner {
    revert('Disabled');
  }

  function platformPositionUnits() external view returns (uint256) {
    return platform.totalPositionUnitsAmount();
  }

  function vaultPositionUnits() external view returns (uint256) {
    (, uint256 dexVolTokensAmount, , uint256 dexUSDCAmount) = getReserves();
    if (IERC20(address(volToken)).totalSupply() == 0 || (dexVolTokensAmount == 0 && dexUSDCAmount == 0)) {
      return 0;
    }

    (uint256 totalPositionUnits, , , , ) = platform.positions(address(volToken));
    return (totalPositionUnits * getVaultDEXVolTokens()) / IERC20(address(volToken)).totalSupply();
  }

  function setRewardRouter(IRewardRouter _rewardRouter, IRewardTracker _rewardTracker) external override onlyOwner {
    rewardRouter = _rewardRouter;
  }

  function setFulfiller(address _newFulfiller) external override onlyOwner {
    fulfiller = _newFulfiller;
  }

  function setMinAmounts(uint256 _newMinDepositAmount, uint256 _newMinWithdrawAmount) external override onlyOwner {
    minDepositAmount = _newMinDepositAmount;
    minWithdrawAmount = _newMinWithdrawAmount;
  }

  function setDepositHoldings(uint16 _newDepositHoldingsPercentage) external override onlyOwner {
    depositHoldingsPercentage = _newDepositHoldingsPercentage;
  }

  function setMinPoolSkew(uint16 _newMinPoolSkewPercentage) external override onlyOwner {
    minPoolSkewPercentage = _newMinPoolSkewPercentage;
  }

  function setLiquidityPercentages(uint16 _newExtraLiquidityPercentage, uint16 _minDexPercentageAllowed)
    external
    override
    onlyOwner
  {
    extraLiquidityPercentage = _newExtraLiquidityPercentage;
    minDexPercentageAllowed = _minDexPercentageAllowed;
  }

  function setRequestDelay(uint256 _newRequestDelay) external override onlyOwner {
    requestDelay = _newRequestDelay;
  }

  function setDepositCap(uint256 _newDepositCap) external override onlyOwner {
    depositCap = _newDepositCap;
  }

  function setPeriods(uint256 _newLockupPeriod, uint256 _newLiquidationPeriod) external override onlyOwner {
    lockupPeriod = _newLockupPeriod;
    liquidationPeriod = _newLiquidationPeriod;
  }

  function totalBalance()
    public
    view
    override
    returns (
      uint256 balance,
      uint256 usdcPlatformLiquidity,
      uint256 intrinsicDEXVolTokenBalance,
      uint256 volTokenPositionBalance,
      uint256 dexUSDCAmount,
      uint256 dexVolTokensAmount
    )
  {
    balance = token.balanceOf(address(this));
    return (balance, 0, 0, 0, 0, 0);
  }

  function burnVolTokens(uint256 _tokensToBurn) internal returns (uint256 burnedVolTokensUSDCAmount) {
    uint168 __tokensToBurn = uint168(_tokensToBurn);
    require(__tokensToBurn == _tokensToBurn); // Sanity, should very rarely fail
    burnedVolTokensUSDCAmount = volToken.burnTokens(__tokensToBurn);
  }

  function isLiquidable(uint256 _requestId) private view returns (bool) {
    return (requests[_requestId].targetTimestamp + liquidationPeriod < block.timestamp);
  }

  function _liquidateRequest(uint256 _requestId) private {
    Request memory request = requests[_requestId];

    if (request.requestType == DEPOSIT_REQUEST_TYPE) {
      totalDepositRequestsAmount -= request.tokenAmount;
    }

    deleteRequest(_requestId);

    if (request.requestType == WITHDRAW_REQUEST_TYPE) {
      IERC20(address(this)).safeTransfer(request.owner, request.tokenAmount);
    } else {
      token.safeTransfer(request.owner, request.tokenAmount);
    }

    emit LiquidateRequest(_requestId, request.requestType, request.owner, msg.sender, request.tokenAmount);
  }

  function deleteRequest(uint256 _requestId) private {
    delete requests[_requestId];

    uint256 currMinRequestId = minRequestId;
    uint256 increments = 0;
    bool didIncrement = false;

    while (
      currMinRequestId < nextRequestId &&
      increments < maxMinRequestIncrements &&
      requests[currMinRequestId].owner == address(0)
    ) {
      increments++;
      currMinRequestId++;
      didIncrement = true;
    }

    if (didIncrement) {
      minRequestId = currMinRequestId;
    }
  }

  function getReserves()
    public
    view
    returns (
      bool canAddLiquidity,
      uint256 volTokenAmount,
      uint256 dexUSDCAmountByVolToken,
      uint256 usdcAmount
    )
  {
    return (false, 0, 0, 0);
  }

  function getVaultDEXVolTokens() internal view returns (uint256 vaultDEXVolTokens) {
    (, uint256 dexVolTokensAmount, , ) = getReserves();

    IERC20 poolPair = IERC20(address(getPair()));
    vaultDEXVolTokens = (dexVolTokensAmount * poolPair.balanceOf(address(this))) / poolPair.totalSupply();
  }

  function getPair() private view returns (IUniswapV2Pair pair) {
    return IUniswapV2Pair(IUniswapV2Factory(router.factory()).getPair(address(volToken), address(token)));
  }
}

