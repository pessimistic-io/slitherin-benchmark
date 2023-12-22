// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import {IPolicyPool} from "./IPolicyPool.sol";
import {IPolicyHolder} from "./IPolicyHolder.sol";
import {WadRayMath} from "./WadRayMath.sol";

import {SafeCast} from "./SafeCast.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IERC20Metadata} from "./IERC20Metadata.sol";

import {ISwapRouter} from "./ISwapRouter.sol";

import {AutomateTaskCreator} from "./AutomateTaskCreator.sol";
import {Module, ModuleData} from "./Types.sol";
import {IWETH9} from "./IWETH9.sol";

import {IPriceRiskModule} from "./IPriceRiskModule.sol";
import {IPriceOracle} from "./IPriceOracle.sol";

import {PayoutAutomationBase} from "./PayoutAutomationBase.sol";

// import "hardhat/console.sol";

abstract contract PayoutAutomationBaseGelato is AutomateTaskCreator, PayoutAutomationBase {
  using SafeERC20 for IERC20Metadata;
  using WadRayMath for uint256;
  using SafeCast for uint256;

  uint256 internal constant WAD = 1e18;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  uint256 internal immutable _wadToCurrencyFactor;
  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IWETH9 internal immutable weth;

  struct SwapParams {
    ISwapRouter swapRouter;
    uint24 feeTier;
  }

  SwapParams internal _swapParams;

  /**
   * @dev Oracle for the price of gas tokens in the currency of the policy pool
   */
  IPriceOracle internal _oracle;

  /**
   * @dev Tolerance, in percentage Wad, for price slippage when swapping currency for gas tokens
   */
  uint256 internal _priceTolerance;

  /**
   * @dev Mapping from policyId to taskIds
   */
  mapping(uint256 => bytes32) private _taskIds;

  event OracleSet(IPriceOracle oracle);
  event SwapRouterSet(ISwapRouter swapRouter);
  event FeeTierSet(uint24 feeTier);
  event PriceToleranceSet(uint256 priceTolerance);

  /**
   * @param policyPool_ Address of the policy pool
   * @param _automate Address of the Gelato's Automate contract
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  // solhint-disable-next-line no-empty-blocks
  constructor(
    IPolicyPool policyPool_,
    address automate_,
    IWETH9 weth_
  ) AutomateTaskCreator(automate_, address(this)) PayoutAutomationBase(policyPool_) {
    require(
      address(weth_) != address(0),
      "PayoutAutomationBaseGelato: WETH address cannot be zero"
    );
    weth = weth_;
    _wadToCurrencyFactor = (10**(18 - _policyPool.currency().decimals()));
  }

  function __PayoutAutomationBaseGelato_init(
    string memory name_,
    string memory symbol_,
    address admin,
    IPriceOracle oracle_,
    ISwapRouter swapRouter_,
    uint24 feeTier_
  ) internal onlyInitializing {
    __PayoutAutomationBase_init(name_, symbol_, admin);
    __PayoutAutomationBaseGelato_init_unchained(oracle_, swapRouter_, feeTier_);
  }

  function __PayoutAutomationBaseGelato_init_unchained(
    IPriceOracle oracle_,
    ISwapRouter swapRouter_,
    uint24 feeTier_
  ) internal onlyInitializing {
    require(
      address(oracle_) != address(0),
      "PayoutAutomationBaseGelato: oracle address cannot be zero"
    );
    _oracle = oracle_;
    emit OracleSet(oracle_);

    require(
      address(swapRouter_) != address(0),
      "PayoutAutomationBaseGelato: SwapRouter address cannot be zero"
    );
    _swapParams.swapRouter = swapRouter_;
    _policyPool.currency().safeApprove(address(_swapParams.swapRouter), type(uint256).max);
    emit SwapRouterSet(swapRouter_);

    require(feeTier_ > 0, "PayoutAutomationBaseGelato: feeTier cannot be zero");
    _swapParams.feeTier = feeTier_;
    emit FeeTierSet(feeTier_);

    _priceTolerance = 2e16; // 2%
    emit PriceToleranceSet(_priceTolerance);
  }

  /**
   * @inheritdoc IPolicyHolder
   */
  function onPayoutReceived(
    address, // riskModule, ignored
    address, // from - Must be the PolicyPool, ignored too. Not too relevant this parameter
    uint256 tokenId,
    uint256 amount
  ) external virtual override onlyPolicyPool returns (bytes4) {
    address paymentReceiver = ownerOf(tokenId);
    _burn(tokenId);
    _cancelTask(_taskIds[tokenId]);
    uint256 remaining = _payTxFee(amount);
    _handlePayout(paymentReceiver, remaining);
    return IPolicyHolder.onPayoutReceived.selector;
  }

  /**
   * @inheritdoc IPolicyHolder
   */
  function onPolicyExpired(
    address,
    address,
    uint256 tokenId
  ) external virtual override onlyPolicyPool returns (bytes4) {
    _burn(tokenId);
    _cancelTask(_taskIds[tokenId]);
    return IPolicyHolder.onPolicyExpired.selector;
  }

  /**
   * @dev Pay gelato for the transaction fee
   * @param amount The payout amount that was received
   * @return The remaining amount after paying the transaction fee
   */
  function _payTxFee(uint256 amount) internal virtual returns (uint256) {
    (uint256 fee, address feeToken) = _getFeeDetails();
    require(feeToken == ETH, "Unsupported feeToken for gelato payment");

    uint256 feeInUSDC = (fee.wadMul(_oracle.getCurrentPrice()) / _wadToCurrencyFactor).wadMul(
      WAD + _priceTolerance
    );

    require(
      feeInUSDC < amount,
      "ForwardPayoutAutomationGelato: the payout is not enough to cover the tx fees"
    );

    ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
      tokenIn: address(_policyPool.currency()),
      tokenOut: address(weth),
      fee: _swapParams.feeTier,
      recipient: address(this),
      deadline: block.timestamp,
      amountOut: fee,
      amountInMaximum: feeInUSDC,
      sqrtPriceLimitX96: 0 // Since we're limiting the transfer amount, we don't need to worry about the price impact of the transaction
    });

    uint256 actualFeeInUSDC = _swapParams.swapRouter.exactOutputSingle(params);

    // Sanity check
    require(
      actualFeeInUSDC <= feeInUSDC,
      "ForwardPayoutAutomationGelato: exchange rate higher than tolerable"
    );

    // Convert the WMATIC to MATIC for fee payment
    weth.withdraw(fee);
    _transfer(fee, feeToken);

    return amount - actualFeeInUSDC;
  }

  /**
   * @inheritdoc PayoutAutomationBase
   */
  function newPolicy(
    IPriceRiskModule riskModule,
    uint256 triggerPrice,
    bool lower,
    uint256 payout,
    uint40 expiration,
    address onBehalfOf
  ) public virtual override returns (uint256 policyId) {
    policyId = super.newPolicy(riskModule, triggerPrice, lower, payout, expiration, onBehalfOf);
    ModuleData memory moduleData = ModuleData({modules: new Module[](1), args: new bytes[](1)});
    moduleData.modules[0] = Module.RESOLVER;
    moduleData.args[0] = _resolverModuleArg(
      address(this),
      abi.encodeCall(this.checker, (riskModule, policyId))
    );

    _taskIds[policyId] = _createTask(
      address(riskModule),
      abi.encode(riskModule.triggerPolicy.selector),
      moduleData,
      ETH
    );
  }

  /**
   *
   * @dev Checks if the resolution task for a given policy can be executed
   * @return canExec true only if the policy can be triggered
   * @return execPayload ABI encoded call data to trigger the policy.
   *                     Notice that the contract that will be called was defined on task creation.
   */
  function checker(IPriceRiskModule riskModule, uint256 policyId)
    external
    view
    returns (bool canExec, bytes memory execPayload)
  {
    canExec = riskModule.policyCanBeTriggered(policyId);
    execPayload = abi.encodeCall(riskModule.triggerPolicy, (policyId));
  }

  function oracle() external view returns (IPriceOracle) {
    return _oracle;
  }

  function setOracle(IPriceOracle oracle_) external onlyRole(GUARDIAN_ROLE) {
    require(
      address(oracle_) != address(0),
      "PayoutAutomationBaseGelato: oracle address cannot be zero"
    );
    _oracle = oracle_;

    emit OracleSet(oracle_);
  }

  function swapRouter() external view returns (ISwapRouter) {
    return _swapParams.swapRouter;
  }

  function setSwapRouter(ISwapRouter swapRouter_) external onlyRole(GUARDIAN_ROLE) {
    require(
      address(swapRouter_) != address(0),
      "PayoutAutomationBaseGelato: SwapRouter address cannot be zero"
    );
    address oldRouter = address(_swapParams.swapRouter);
    _swapParams.swapRouter = swapRouter_;

    _policyPool.currency().safeApprove(oldRouter, 0);
    _policyPool.currency().safeApprove(address(swapRouter_), type(uint256).max);

    emit SwapRouterSet(swapRouter_);
  }

  function feeTier() external view returns (uint24) {
    return _swapParams.feeTier;
  }

  function setFeeTier(uint24 feeTier_) external onlyRole(GUARDIAN_ROLE) {
    require(feeTier_ > 0, "PayoutAutomationBaseGelato: feeTier cannot be zero");
    _swapParams.feeTier = feeTier_;
    emit FeeTierSet(feeTier_);
  }

  function priceTolerance() external view returns (uint256) {
    return _priceTolerance;
  }

  function setPriceTolerance(uint256 priceTolerance_) external onlyRole(GUARDIAN_ROLE) {
    require(priceTolerance_ > 0, "PayoutAutomationBaseGelato: priceTolerance cannot be zero");
    _priceTolerance = priceTolerance_;
    emit PriceToleranceSet(priceTolerance_);
  }

  // Need to receive gas tokens when unwrapping.
  receive() external payable {}

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[46] private __gap;
}

