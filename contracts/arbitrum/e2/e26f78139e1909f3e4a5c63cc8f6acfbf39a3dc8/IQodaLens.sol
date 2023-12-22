//SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.9 <=0.8.19;

import "./QTypes.sol";
import "./QTypesPeripheral.sol";
import "./IFixedRateMarket.sol";

interface IQodaLens {

  /// @notice Gets the first N `Quote`s for a given `FixedRateMarket` and
  /// `side`, filtering for only if the quoter has the requisite hypothetical
  /// collateral ratio and allowance/balance for borrow and lend `Quote`s,
  /// respectively.
  /// For convenience, this function also returns the associated current
  /// collateral ratio and underlying balance of the publisher for the `Quote`.
  /// @param market Market to query
  /// @param side 0 for borrow `Quote`s, 1 for lend `Quote`s
  /// @param n Maximum number of `Quote`s to return
  /// @return QTypes.Quote[], uint[] `collateralRatio`s, uint[] underlying balances
  function takeNFilteredQuotes(
                               IFixedRateMarket market,
                               uint8 side,
                               uint n
                               ) external view returns(QTypes.Quote[] memory, uint[] memory, uint[] memory);
  
  /// @notice Gets the first N `Quote`s for a given `FixedRateMarket` and `side`.
  /// For convenience, this function also returns the associated current
  /// collateral ratio and underlying balance of the publisher for the `Quote`.
  /// @param market Market to query
  /// @param side 0 for borrow `Quote`s, 1 for lend `Quote`s
  /// @param n Maximum number of `Quote`s to return
  /// @return QTypes.Quote[], uint[] `collateralRatio`s, uint[] underlying balances
  function takeNQuotes(
                       IFixedRateMarket market,
                       uint8 side,
                       uint n
                       ) external view returns(QTypes.Quote[] memory, uint[] memory, uint[] memory);
  
  /// @notice Gets all open quotes from all unexpired market for a given account
  /// @param account Account for getting all open quotes
  /// @return QTypesPeripheral.AccountQuote[] Related quotes for given account
  function takeAccountQuotes(address account) external view returns (QTypesPeripheral.AccountQuote[] memory);

  /// @notice Convenience function to convert an array of `Quote` ids to
  /// an array of the underlying `Quote` structs
  /// @param market Market to query
  /// @param side 0 for borrow `Quote`s, 1 for lend `Quote`s
  /// @param quoteIds array of `Quote` ids to query
  /// @return QTypes.Quote[] Ordered array of `Quote`s corresponding to `Quote` ids
  function quoteIdsToQuotes(
                            IFixedRateMarket market,
                            uint8 side,
                            uint64[] calldata quoteIds
                            ) external view returns(QTypes.Quote[] memory);

  /// @notice Get the weighted average estimated APR for a requested market
  /// order `size`. The estimated APR is the weighted average of the first N
  /// `Quote`s APR until the full `size` is satisfied. The `size` can be in
  /// either PV terms or FV terms. This function also returns the confirmed
  /// filled amount in the case that the entire list of `Quote`s in the
  /// orderbook is smaller than the requested size. It returns default (0,0) if
  /// the orderbook is currently empty.
  /// @param market Market to query
  /// @param account Account to view estimated APR from
  /// @param size Size requested by the user. Can be in either PV or FV terms
  /// @param side 0 for borrow `Quote`s, 1 for lend `Quote`s
  /// @param quoteType 0 for PV, 1 for FV
  /// @return uint Estimated APR, scaled by 1e4, uint Confirmed filled size
  function getEstimatedAPR(
                           IFixedRateMarket market,
                           address account,
                           uint size,
                           uint8 side,
                           uint8 quoteType
                           ) external view returns(uint, uint);
  
  /// @notice Get an account's maximum available collateral user can withdraw in specified asset.
  /// For example, what is the maximum amount of GLMR that an account can withdraw
  /// while ensuring their account health continues to be acceptable?
  /// Note: This function will return withdrawable amount that user has indeed collateralized, not amount that user can borrow
  /// Note: User can only withdraw up to `initCollateralRatio` for their own protection against instant liquidations
  /// Note: Design decision: asset-enabled check not done as collateral can be disabled after
  /// @param account User account
  /// @param withdrawToken Currency of collateral to withdraw
  /// @return uint Maximum available collateral user can withdraw in specified asset
  function hypotheticalMaxWithdraw(address account, address withdrawToken) external view returns (uint);
  
  /// @notice Get an account's maximum available borrow amount in a specific FixedRateMarket.
  /// For example, what is the maximum amount of GLMRJUL22 that an account can borrow
  /// while ensuring their account health continues to be acceptable?
  /// Note: This function will return 0 if market to borrow is disabled
  /// Note: This function will return creditLimit() if maximum amount allowed for one market exceeds creditLimit()
  /// Note: User can only borrow up to `initCollateralRatio` for their own protection against instant liquidations
  /// @param account User account
  /// @param borrowMarket Address of the `FixedRateMarket` market to borrow
  /// @return uint Maximum available amount user can borrow (in FV) without breaching `initCollateralRatio`
  function hypotheticalMaxBorrowFV(address account, IFixedRateMarket borrowMarket) external view returns (uint);
  
  /// @notice Get an account's maximum value user can lend in specified market when protocol fee is factored in.
  /// @param account User account
  /// @param lendMarket Address of the `FixedRateMarket` market to lend
  /// @return uint Maximum value user can lend in specified market with protocol fee considered
  function hypotheticalMaxLendPV(address account, IFixedRateMarket lendMarket) external view returns (uint);
  
  /// @notice Get an account's minimum collateral to further deposit if user wants to borrow specified amount in a certain market.
  /// For example, what is the minimum amount of USDC to deposit so that an account can borrow 100 DEV token from qDEVJUL22
  /// while ensuring their account health continues to be acceptable?
  /// @param account User account
  /// @param collateralToken Currency to collateralize in
  /// @param borrowMarket Address of the `FixedRateMarket` market to borrow
  /// @param borrowAmount Amount to borrow in local ccy
  /// @return uint Minimum collateral required to further deposit
  function minimumCollateralRequired(
                                     address account,
                                     IERC20 collateralToken,
                                     IFixedRateMarket borrowMarket,
                                     uint borrowAmount
                                     ) external view returns (uint);
  
  function getAllMarketsByAsset(IERC20 token) external view returns (IFixedRateMarket[] memory);
      
  function totalLoansTradedByMarket(IFixedRateMarket market) external view returns (uint);
  function totalRedeemedLendsByMarket(IFixedRateMarket market) external view returns (uint);
  function totalUnredeemedLendsByMarket(IFixedRateMarket market) external view returns (uint);
  function totalRepaidBorrowsByMarket(IFixedRateMarket market) external view returns (uint);
  function totalUnrepaidBorrowsByMarket(IFixedRateMarket market) external view returns (uint);
  
  function totalLoansTradedByAsset(IERC20 token) external view returns (uint);
  function totalRedeemedLendsByAsset(IERC20 token) external view returns (uint);
  function totalUnredeemedLendsByAsset(IERC20 token) external view returns (uint);
  function totalRepaidBorrowsByAsset(IERC20 token) external view returns (uint);
  function totalUnrepaidBorrowsByAsset(IERC20 token) external view returns (uint);
  
  function totalLoansTradedInUSD() external view returns (uint);
  function totalRedeemedLendsInUSD() external view returns (uint);
  function totalUnredeemedLendsInUSD() external view returns (uint);
  function totalRepaidBorrowsInUSD() external view returns (uint);
  function totalUnrepaidBorrowsInUSD() external view returns (uint);
    
  /// @notice Get the address of the `QollateralManager` contract
  /// @return address Address of `QollateralManager` contract
  function qollateralManager() external view returns(address);
  
  /// @notice Get the address of the `QAdmin` contract
  /// @return address Address of `QAdmin` contract
  function qAdmin() external view returns(address);
  
  /// @notice Get the address of the `QPriceOracle` contract
  /// @return address Address of `QPriceOracle` contract
  function qPriceOracle() external view returns(address);
}

