//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IERC20Upgradeable.sol";
import "./IERC20MetadataUpgradeable.sol";
import "./IERC20.sol";

interface IQToken is IERC20Upgradeable, IERC20MetadataUpgradeable {
  
  /// @notice Emitted when an account redeems their qTokens
  event RedeemQTokens(address indexed account, uint amount);
  
  /** USER INTERFACE **/
  
  /// @notice This function allows net lenders to redeem qTokens for the
  /// underlying token. Redemptions may only be permitted after loan maturity
  /// plus `_maturityGracePeriod`. The public interface redeems specified amount
  /// of qToken from existing balance.
  /// @param amount Amount of qTokens to redeem
  /// @return uint Amount of qTokens redeemed
  function redeemQTokensByRatio(uint amount) external returns(uint);
  
  /// @notice This function allows net lenders to redeem qTokens for the
  /// underlying token. Redemptions may only be permitted after loan maturity
  /// plus `_maturityGracePeriod`. The public interface redeems the entire qToken
  /// balance.
  /// @return uint Amount of qTokens redeemed
  function redeemAllQTokensByRatio() external returns(uint);
  
  /// @notice This function allows net lenders to redeem qTokens for ETH.
  /// Redemptions may only be permitted after loan maturity plus 
  /// `_maturityGracePeriod`. The public interface redeems specified amount
  /// of qToken from existing balance.
  /// @param amount Amount of qTokens to redeem
  /// @return uint Amount of qTokens redeemed
  function redeemQTokensByRatioWithETH(uint amount) external returns(uint);
  
  /// @notice This function allows net lenders to redeem qTokens for ETH.
  /// Redemptions may only be permitted after loan maturity plus
  /// `_maturityGracePeriod`. The public interface redeems the entire qToken
  /// balance.
  /// @return uint Amount of qTokens redeemed
  function redeemAllQTokensByRatioWithETH() external returns(uint);
  
  /** VIEW FUNCTIONS **/
  
  /// @notice Get the address of the `QAdmin`
  /// @return address
  function qAdmin() external view returns(address);
  
  /// @notice Gets the address of the `FixedRateMarket` contract
  /// @return address Address of `FixedRateMarket` contract
  function fixedRateMarket() external view returns(address);
  
  /// @notice Get the address of the ERC20 token which the loan will be denominated
  /// @return IERC20
  function underlyingToken() external view returns(IERC20);
  
  /// @notice Get amount of qTokens user can redeem based on current loan repayment ratio
  /// @return uint amount of qTokens user can redeem
  function redeemableQTokens() external view returns(uint);
  
  /// @notice Gets the current `redemptionRatio` where owned qTokens can be redeemed up to
  /// @return uint redemption ratio, capped and scaled by 1e18
  function redemptionRatio() external view returns(uint);
  
  /// @notice Tokens redeemed from message sender so far
  /// @return uint Token redeemed by message sender
  function tokensRedeemed() external view returns(uint);
  
  /// @notice Tokens redeemed from given account so far
  /// @param account Account to query
  /// @return uint Token redeemed by given account
  function tokensRedeemed(address account) external view returns(uint);
  
  /// @notice Tokens redeemed across all users so far
  function tokensRedeemedTotal() external view returns(uint);
  
  /** ERC20 Implementation **/
  
  /// @notice Creates `amount` tokens and assigns them to `account`, increasing the total supply.
  /// @param account Account to receive qToken
  /// @param amount Amount of qToken to mint
  function mint(address account, uint256 amount) external;
  
  /// @notice Destroys `amount` tokens from `account`, reducing the total supply
  /// @param account Account to receive qToken
  /// @param amount Amount of qToken to mint
  function burn(address account, uint256 amount) external;
}
