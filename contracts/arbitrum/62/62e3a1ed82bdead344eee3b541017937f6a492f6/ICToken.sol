//  SPDX-License-Identifier: UNLICENSED
pragma solidity >= 0.8.10;

import {IERC20Metadata as IERC20} from "./extensions_IERC20Metadata.sol";
import {IGlpManager} from "./IGlpManager.sol";
import {IRewardRouterV2} from "./IRewardRouterV2.sol";
import {IStakedGlp} from "./IStakedGlp.sol";
import {IRewardTracker} from "./IRewardTracker.sol";
import {IComptroller} from "./IComptroller.sol";
import {InterestRateModel} from "./InterestRateModel.sol";

interface ICToken is IERC20 {
  // CERC20 functions
  function underlying() external view returns (IERC20);
  function mintForAccount(address account, uint256 mintAmount) external returns (uint256);
  function mint(uint256 mintAmount) external returns (uint256);
  function redeem(uint256 redeemTokens) external returns (uint256);
  function redeemForAccount(address account, uint256 redeemTokens) external returns (uint256);
  function redeemUnderlyingForAccount(address account, uint256 redeemAmount)
    external
    returns (uint256);

  function redeemUnderlying(uint256 redeemAmount) external returns (uint256);
  function redeemUnderlyingForUser(uint256 redeemAmount, address user) external returns (uint256);
  function borrow(uint256 borrowAmount) external returns (uint256);
  function borrowForAccount(address account, uint256 borrowAmount) external returns (uint256);
  function repayForAccount(address borrower, uint256 repayAmount) external returns (uint256);
  function repayBorrow(uint256 repayAmount) external returns (uint256);
  function repayBorrowBehalf(address borrower, uint256 repayAmount) external returns (uint256);
  function liquidateBorrow(address borrower, uint256 repayAmount, address cTokenCollateral)
    external
    returns (uint256);
  function depositNFT(address _NFTAddress, uint256 _TokenID) external;
  function withdrawNFT(address _NFTAddress, uint256 _TokenID) external;
  function compound() external returns (uint256);

  // CToken functions
  function glpManager() external view returns (IGlpManager);
  function gmxToken() external view returns (IERC20);
  function glpRewardRouter() external view returns (IRewardRouterV2);
  function stakedGLP() external view returns (IStakedGlp);
  function sbfGMX() external view returns (IRewardTracker);
  function stakedGmxTracker() external view returns (IRewardTracker);

  function _notEntered() external view returns (bool);

  function isGLP() external view returns (bool);
  function autocompound() external view returns (bool);
  function glpBlockDelta() external view returns (uint256);
  function lastGlpDepositAmount() external view returns (uint256);

  function comptroller() external view returns (IComptroller);
  function interestRateModel() external view returns (InterestRateModel);

  function name() external view returns (string memory);
  function symbol() external view returns (string memory);
  function decimals() external view returns (uint8);
  function admin() external view returns (address);
  function pendingAdmin() external view returns (address);
  function initialExchangeRateMantissa() external view returns (uint256);
  function reserveFactorMantissa() external view returns (uint256);
  function accrualBlockNumber() external view returns (uint256);
  function borrowIndex() external view returns (uint256);
  function totalBorrows() external view returns (uint256);
  function totalReserves() external view returns (uint256);
  function totalSupply() external view returns (uint256);
  function withdrawFee() external view returns (uint256);
  function performanceFee() external view returns (uint256);
  function exchangeRateBefore() external view returns (uint256);
  function blocksBetweenRateChange() external view returns (uint256);
  function prevExchangeRate() external view returns (uint256);
  function depositsDuringLastInterval() external view returns (uint256);
  function isCToken() external view returns (bool);

  function performanceFeeMAX() external view returns (uint256);
  function withdrawFeeMAX() external view returns (uint256);
  function autoCompoundBlockThreshold() external view returns (uint256);

  event AccrueInterest(
    uint256 cashPrior, uint256 interestAccumulated, uint256 borrowIndex, uint256 totalBorrows
  );
  event Mint(address minter, uint256 mintAmount, uint256 mintTokens);
  event Redeem(address redeemer, uint256 redeemAmount, uint256 redeemTokens);
  event Borrow(
    address borrower, uint256 borrowAmount, uint256 accountBorrows, uint256 totalBorrows
  );
  event RepayBorrow(
    address payer,
    address borrower,
    uint256 repayAmount,
    uint256 accountBorrows,
    uint256 totalBorrows
  );
  event LiquidateBorrow(
    address liquidator,
    address borrower,
    uint256 repayAmount,
    address cTokenCollateral,
    uint256 seizeTokens
  );
  event NewPendingAdmin(address oldPendingAdmin, address newPendingAdmin);
  event NewAdmin(address oldAdmin, address newAdmin);
  event NewComptroller(IComptroller oldComptroller, IComptroller newComptroller);
  event NewMarketInterestRateModel(
    InterestRateModel oldInterestRateModel, InterestRateModel newInterestRateModel
  );
  event NewReserveFactor(uint256 oldReserveFactorMantissa, uint256 newReserveFactorMantissa);
  event ReservesAdded(address benefactor, uint256 addAmount, uint256 newTotalReserves);
  event ReservesReduced(address admin, uint256 reduceAmount, uint256 newTotalReserves);

  function transfer(address dst, uint256 amount) external returns (bool);
  function transferFrom(address src, address dst, uint256 amount) external returns (bool);
  function approve(address spender, uint256 amount) external returns (bool);
  function allowance(address owner, address spender) external view returns (uint256);
  function balanceOf(address owner) external view returns (uint256);
  function balanceOfUnderlying(address owner) external returns (uint256);
  function getAccountSnapshot(address account)
    external
    view
    returns (uint256, uint256, uint256, uint256);
  function borrowRatePerBlock() external view returns (uint256);
  function supplyRatePerBlock() external view returns (uint256);
  function totalBorrowsCurrent() external returns (uint256);
  function borrowBalanceCurrent(address account) external returns (uint256);
  function borrowBalanceStored(address account) external view returns (uint256);
  function exchangeRateCurrent() external returns (uint256);
  function exchangeRateStored() external view returns (uint256);
  function getCash() external view returns (uint256);
  function accrueInterest() external returns (uint256);
  function seize(address liquidator, address borrower, uint256 seizeTokens)
    external
    returns (uint256);

  /**
   * Admin Functions **
   */
  function _setPendingAdmin(address payable newPendingAdmin) external returns (uint256);
  function _acceptAdmin() external returns (uint256);
  function _setComptroller(IComptroller newComptroller) external returns (uint256);
  function _setReserveFactor(uint256 newReserveFactorMantissa) external returns (uint256);
  function _reduceReserves(uint256 reduceAmount) external returns (uint256);
  function _setInterestRateModel(InterestRateModel newInterestRateModel) external returns (uint256);
}

