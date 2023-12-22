// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import {IHook} from "./IHook.sol";
import {IAddressBeacon, ICollateral, IERC20, ILongShortToken, IPrePOMarket, IUintBeacon} from "./IPrePOMarket.sol";
import {SafeAccessControlEnumerable} from "./SafeAccessControlEnumerable.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";

contract PrePOMarket is
  IPrePOMarket,
  ReentrancyGuard,
  SafeAccessControlEnumerable
{
  ILongShortToken private immutable _longToken;
  ILongShortToken private immutable _shortToken;

  IAddressBeacon private immutable _addressBeacon;
  IUintBeacon private immutable _uintBeacon;

  ICollateral private immutable _collateral;

  uint256 private immutable _floorLongPayout;
  uint256 private immutable _ceilingLongPayout;
  uint256 private immutable _expiryLongPayout;
  uint256 private _finalLongPayout;

  uint256 private immutable _floorValuation;
  uint256 private immutable _ceilingValuation;

  uint256 private immutable _expiryTime;

  uint256 public constant override PERCENT_UNIT = 1000000;
  uint256 public constant override FEE_LIMIT = 100000;

  bytes32 public constant override SET_FINAL_LONG_PAYOUT_ROLE =
    keccak256("setFinalLongPayout");

  bytes32 public constant override MINT_HOOK_KEY = keccak256("MarketMintHook");
  bytes32 public constant override REDEEM_HOOK_KEY =
    keccak256("MarketRedeemHook");
  bytes32 public constant override MINT_FEE_PERCENT_KEY =
    keccak256("MarketMintFeePercent");
  bytes32 public constant override REDEEM_FEE_PERCENT_KEY =
    keccak256("MarketRedeemFeePercent");

  /**
   * Assumes `_collateral`, `_longToken`, and `_shortToken` are
   * valid, since they will be handled by the PrePOMarketFactory.
   *
   * Assumes that ownership of `_longToken` and `_shortToken` has been
   * transferred to this contract via `createMarket()` in
   * `PrePOMarketFactory.sol`.
   */
  constructor(
    address deployer,
    ILongShortToken longToken,
    ILongShortToken shortToken,
    IAddressBeacon addressBeacon,
    IUintBeacon uintBeacon,
    IPrePOMarket.MarketParameters memory parameters
  ) {
    if (parameters.ceilingLongPayout <= parameters.floorLongPayout)
      revert CeilingNotAboveFloor();
    if (parameters.ceilingLongPayout > 1e18) revert CeilingTooHigh();
    if (parameters.expiryLongPayout < parameters.floorLongPayout)
      revert FinalPayoutTooLow();
    if (parameters.expiryLongPayout > parameters.ceilingLongPayout)
      revert FinalPayoutTooHigh();
    if (block.timestamp >= parameters.expiryTime) revert ExpiryInPast();
    _revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(SET_FINAL_LONG_PAYOUT_ROLE, deployer);
    _setRoleAdmin(SET_FINAL_LONG_PAYOUT_ROLE, SET_FINAL_LONG_PAYOUT_ROLE);
    _longToken = longToken;
    _shortToken = shortToken;
    _addressBeacon = addressBeacon;
    _uintBeacon = uintBeacon;
    _collateral = ICollateral(parameters.collateral);
    _floorLongPayout = parameters.floorLongPayout;
    _ceilingLongPayout = parameters.ceilingLongPayout;
    _expiryLongPayout = parameters.expiryLongPayout;
    _finalLongPayout = type(uint256).max;
    _floorValuation = parameters.floorValuation;
    _ceilingValuation = parameters.ceilingValuation;
    _expiryTime = parameters.expiryTime;
  }

  function mint(
    uint256 collateralAmount,
    address recipient,
    bytes calldata data
  ) external override nonReentrant returns (uint256) {
    return _mint(collateralAmount, recipient, data);
  }

  function permitAndMint(
    Permit calldata permit,
    uint256 collateralAmount,
    address recipient,
    bytes calldata data
  ) external override nonReentrant returns (uint256) {
    if (permit.deadline != 0) {
      _collateral.permit(
        msg.sender,
        address(this),
        type(uint256).max,
        permit.deadline,
        permit.v,
        permit.r,
        permit.s
      );
    }
    return _mint(collateralAmount, recipient, data);
  }

  function redeem(
    uint256 longAmount,
    uint256 shortAmount,
    address recipient,
    bytes calldata data
  ) external override nonReentrant {
    if (longAmount > _longToken.balanceOf(msg.sender))
      revert InsufficientLongToken();
    if (shortAmount > _shortToken.balanceOf(msg.sender))
      revert InsufficientShortToken();
    uint256 collateralAmount;
    if (_finalLongPayout != type(uint256).max) {
      uint256 shortPayout = 1e18 - _finalLongPayout;
      collateralAmount =
        (_finalLongPayout * longAmount + shortPayout * shortAmount) /
        1e18;
    } else {
      if (longAmount != shortAmount) revert UnequalRedemption();
      collateralAmount = longAmount;
    }
    uint256 collateralFeeAmount = _processFee(
      REDEEM_HOOK_KEY,
      REDEEM_FEE_PERCENT_KEY,
      collateralAmount,
      recipient,
      data
    );
    if (longAmount > 0) _longToken.burnFrom(msg.sender, longAmount);
    if (shortAmount > 0) _shortToken.burnFrom(msg.sender, shortAmount);
    uint256 collateralAmountAfterFee = collateralAmount - collateralFeeAmount;
    _collateral.transfer(recipient, collateralAmountAfterFee);
    emit Redemption(
      msg.sender,
      recipient,
      collateralAmountAfterFee,
      collateralFeeAmount
    );
  }

  function setFinalLongPayout(uint256 finalLongPayout)
    external
    override
    onlyRole(SET_FINAL_LONG_PAYOUT_ROLE)
  {
    if (_finalLongPayout <= _ceilingLongPayout) revert MarketEnded();
    if (finalLongPayout < _floorLongPayout) revert FinalPayoutTooLow();
    if (finalLongPayout > _ceilingLongPayout) revert FinalPayoutTooHigh();
    _finalLongPayout = finalLongPayout;
    emit FinalLongPayoutSet(finalLongPayout);
  }

  function setFinalLongPayoutAfterExpiry() external override {
    if (_finalLongPayout <= _ceilingLongPayout) revert MarketEnded();
    if (block.timestamp <= _expiryTime) revert ExpiryNotPassed();
    _finalLongPayout = _expiryLongPayout;
    emit FinalLongPayoutSet(_expiryLongPayout);
  }

  function getLongToken() external view override returns (ILongShortToken) {
    return _longToken;
  }

  function getShortToken() external view override returns (ILongShortToken) {
    return _shortToken;
  }

  function getAddressBeacon() external view override returns (IAddressBeacon) {
    return _addressBeacon;
  }

  function getUintBeacon() external view override returns (IUintBeacon) {
    return _uintBeacon;
  }

  function getCollateral() external view override returns (ICollateral) {
    return _collateral;
  }

  function getFloorLongPayout() external view override returns (uint256) {
    return _floorLongPayout;
  }

  function getCeilingLongPayout() external view override returns (uint256) {
    return _ceilingLongPayout;
  }

  function getExpiryLongPayout() external view override returns (uint256) {
    return _expiryLongPayout;
  }

  function getFinalLongPayout() external view override returns (uint256) {
    return _finalLongPayout;
  }

  function getFloorValuation() external view override returns (uint256) {
    return _floorValuation;
  }

  function getCeilingValuation() external view override returns (uint256) {
    return _ceilingValuation;
  }

  function getExpiryTime() external view override returns (uint256) {
    return _expiryTime;
  }

  function getFeePercent(bytes32 feeKey)
    public
    view
    override
    returns (uint256 feePercent)
  {
    // 20 byte address not directly convertible to bytes32
    uint256 customFeePercent = _uintBeacon.get(
      bytes32(uint256(uint160(address(this))))
    );
    if (customFeePercent != 0) {
      feePercent = customFeePercent == type(uint256).max
        ? 0
        : customFeePercent;
    } else {
      feePercent = _uintBeacon.get(feeKey);
    }
    if (feePercent > FEE_LIMIT) feePercent = FEE_LIMIT;
  }

  function _processFee(
    bytes32 hookKey,
    bytes32 feeKey,
    uint256 collateralAmountBeforeFee,
    address recipient,
    bytes calldata data
  ) internal returns (uint256 actualCollateralFeeAmount) {
    IHook hook = IHook(_addressBeacon.get(hookKey));
    if (address(hook) == address(0)) return 0;
    uint256 feePercent = getFeePercent(feeKey);
    if (feePercent == 0) {
      if (collateralAmountBeforeFee == 0) revert ZeroCollateralAmount();
      hook.hook(
        msg.sender,
        recipient,
        collateralAmountBeforeFee,
        collateralAmountBeforeFee,
        data
      );
      return 0;
    }
    uint256 expectedCollateralFeeAmount = (collateralAmountBeforeFee *
      feePercent) / PERCENT_UNIT;
    if (expectedCollateralFeeAmount == 0) revert FeeRoundsToZero();
    _collateral.approve(address(hook), expectedCollateralFeeAmount);
    uint256 collateralAllowanceBefore = _collateral.allowance(
      address(this),
      address(hook)
    );
    hook.hook(
      msg.sender,
      recipient,
      collateralAmountBeforeFee,
      collateralAmountBeforeFee - expectedCollateralFeeAmount,
      data
    );
    actualCollateralFeeAmount =
      collateralAllowanceBefore -
      _collateral.allowance(address(this), address(hook));
    _collateral.approve(address(hook), 0);
  }

  function _mint(
    uint256 collateralAmount,
    address recipient,
    bytes calldata data
  ) internal returns (uint256 longShortAmount) {
    if (_finalLongPayout <= _ceilingLongPayout) revert MarketEnded();
    if (collateralAmount > _collateral.balanceOf(msg.sender))
      revert InsufficientCollateral();
    _collateral.transferFrom(msg.sender, address(this), collateralAmount);
    uint256 collateralFeeAmount = _processFee(
      MINT_HOOK_KEY,
      MINT_FEE_PERCENT_KEY,
      collateralAmount,
      recipient,
      data
    );
    longShortAmount = collateralAmount - collateralFeeAmount;
    _longToken.mint(recipient, longShortAmount);
    _shortToken.mint(recipient, longShortAmount);
    emit Mint(msg.sender, recipient, longShortAmount, collateralFeeAmount);
  }
}

