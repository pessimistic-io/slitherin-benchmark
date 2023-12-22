//SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.4;

import "./IERC20.sol";
import "./IERC721.sol";
import "./IERC1155.sol";
import "./IAccessControl.sol";

/**
 * @title   Interface of HToken Internal
 * @author  Honey Labs Inc.
 * @custom:coauthor m4rio
 * @custom:coauthor BowTiedPickle
 */
interface HTokenInternalI is IERC1155, IAccessControl {
  struct Coupon {
    uint32 id; //Coupon's id
    uint8 active; // Coupon activity status
    address owner; // Who is the current owner of this coupon
    uint256 collateralId; // tokenId of the collateral collection that is borrowed against
    uint256 borrowAmount; // Principal borrow balance, denominated in underlying ERC20 token.
    uint256 debtShares; // Debt shares, keeps the shares of total debt by the protocol
  }

  struct Collateral {
    uint256 collateralId; // TokenId of the collateral
    bool active; // Collateral activity status
  }

  // ----- Informational -----

  function decimals() external view returns (uint8);

  function name() external view returns (string memory);

  function symbol() external view returns (string memory);

  // ----- Addresses -----

  function collateralToken() external view returns (IERC721);

  function underlyingToken() external view returns (IERC20);

  // ----- Protocol Accounting -----

  function totalBorrows() external view returns (uint256);

  function totalReserves() external view returns (uint256);

  function totalSupply() external view returns (uint256);

  function totalFuseFees() external view returns (uint256);

  function totalAdminCommission() external view returns (uint256);

  function accrualBlockNumber() external view returns (uint256);

  function interestIndexStored() external view returns (uint256);

  function totalProtocolCommission() external view returns (uint256);

  function userToCoupons(address _user) external view returns (uint256);

  function collateralPerBorrowCouponId(uint256 _couponId) external view returns (Collateral memory);

  function borrowCoupons(uint256 _collateralId) external view returns (Coupon memory);

  // ----- Views -----

  /**
   * @notice  Get the outstanding debt of a collateral
   * @dev     Simulates accrual of interest
   * @param   _collateralId   Token ID of underlying ERC-721
   * @return  Outstanding debt in units of underlying ERC-20
   */
  function getDebtForCollateral(uint256 _collateralId) external view returns (uint256);

  /**
   * @notice  Returns the current per-block borrow interest rate for this hToken
   * @return  The borrow interest rate per block, scaled by 1e18
   */
  function borrowRatePerBlock() external view returns (uint256);

  /**
   * @notice  Get the outstanding debt of a coupon
   * @dev     Simulates accrual of interest
   * @param   _couponId   ID of the coupon
   * @return  Outstanding debt in units of underlying ERC-20
   */
  function getDebtForCoupon(uint256 _couponId) external view returns (uint256);

  /**
   * @notice  Gets balance of this contract in terms of the underlying excluding the fees
   * @dev     This excludes the value of the current message, if any
   * @return  The quantity of underlying ERC-20 tokens owned by this contract
   */
  function getCashPrior() external view returns (uint256);

  /**
   * @notice  Get a snapshot of the account's balances, and the cached exchange rate
   * @dev     This is used by controller to more efficiently perform liquidity checks.
   * @param   _account  Address of the account to snapshot
   * @return  (token balance, borrow balance, exchange rate mantissa)
   */
  function getAccountSnapshot(address _account) external view returns (uint256, uint256, uint256);

  /**
   * @notice  Get the outstanding debt of the protocol
   * @return  Protocol debt
   */
  function getDebt() external view returns (uint256);

  /**
   * @notice  Returns protocol fees
   * @return  Reserve factor mantissa
   * @return  Admin commission mantissa
   * @return  Protocol commission mantissa
   * @return  Initial exchange rate mantissa
   * @return  Maximum borrow rate mantissa
   */
  function getProtocolFees() external view returns (uint256, uint256, uint256, uint256, uint256);

  /**
   * @notice  Returns different addresses of the protocol
   * @return  Liquidator address
   * @return  HTokenHelper address
   * @return  Controller address
   * @return  Admin commission receiver address
   * @return  Protocol commission receiver address
   * @return  Interest model address
   * @return  Referral pool address
   * @return  DAO address
   */
  function getAddresses()
    external
    view
    returns (address, address, address, address, address, address, address, address);

  /**
   * @notice  Get the last minted coupon ID
   * @return  The last minted coupon ID
   */
  function idCounter() external view returns (uint256);

  /**
   * @notice  Get the coupon for a specific collateral NFT
   * @param   _collateralId   Token ID of underlying ERC-721
   * @return  Coupon
   */
  function getSpecificCouponByCollateralId(uint256 _collateralId) external view returns (Coupon memory);

  /**
   * @notice  Calculate the prevailing interest due per token of debt principal
   * @return  Mantissa formatted interest rate per token of debt
   */
  function interestIndex() external view returns (uint256);

  /**
   * @notice  Accrue interest then return the up-to-date exchange rate from the ERC-20 underlying to the HToken
   * @return  Calculated exchange rate scaled by 1e18
   */
  function exchangeRateCurrent() external returns (uint256);

  /**
   * @notice  Calculates the exchange rate from the ERC-20 underlying to the HToken
   * @dev     This function does not accrue interest before calculating the exchange rate
   * @return  Calculated exchange rate scaled by 1e18
   */
  function exchangeRateStored() external view returns (uint256);

  /**
   * @notice  Add to or take away from reserves
   * @dev     Accrues interest
   * @param   _amount  Quantity of underlying ERC-20 token to change the reserves by
   */
  function _modifyReserves(uint256 _amount, bool _add) external;

  /**
   * @notice  Set new admin commission mantissas
   * @dev     Accrues interest
   * @param   _newAdminCommissionMantissa        New admin commission mantissa
   */
  function _setAdminCommission(uint256 _newAdminCommissionMantissa) external;

  /**
   * @notice  Set new protocol commission and reserve factor mantissas
   * @dev     Accrues interest
   * @param   _newProtocolCommissionMantissa    New protocol commission mantissa
   * @param   _newReserveFactorMantissa         New reserve factor mantissa
   */
  function _setProtocolFees(uint256 _newProtocolCommissionMantissa, uint256 _newReserveFactorMantissa) external;

  /**
   * @notice  Sets a new admin fee receiver
   * @param   _newAddress   Address of the new admin fee receiver
   * @param   _target       Target ID of the address to be set
   */
  function _setAddressMarketAdmin(address _newAddress, uint256 _target) external;

  /**
   * @notice  Sets a new protocol address parameter
   * @dev     Callable only by DEFAULT_ADMIN_ROLE
   * @dev     Target of 3 is reserved by convention for admin fee receiver
   * @dev     Target of 5 is reserved by convention for interest rate model
   * @param   _newAddress   Address of the new contract
   * @param   _target       Target ID of the address to be set
   */
  function _setAddress(address _newAddress, uint256 _target) external;
}

