//SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.9 <=0.8.19;

import "./IERC20.sol";

interface IQPriceOracle {

  /// @notice Emitted when setting the DIA Oracle address
  event SetDIAOracle(address DIAOracle);

  /// @notice Emitted when setting grace period for IERC20 token
  event SetGracePeriod(address tokenAddress, uint oldValue, uint newValue);

  function _setDIAOracle(address DIAOracleAddr) external;

  function _setGracePeriod(address tokenAddress, uint gracePeriodNew) external;
  
  /// @notice Converts any local value into its value in USD using oracle feed price
  /// @param token ERC20 token
  /// @param amountLocal Amount denominated in terms of the ERC20 token
  /// @return uint Amount in USD
  function localToUSD(IERC20 token, uint amountLocal) external view returns(uint);

  /// @notice Converts any value in USD into its value in local using oracle feed price
  /// @param token ERC20 token
  /// @param valueUSD Amount in USD
  /// @return uint Amount denominated in terms of the ERC20 token
  function USDToLocal(IERC20 token, uint valueUSD) external view returns(uint);

  /// @notice Convenience function for getting price feed from various oracles.
  /// Returned prices should ALWAYS be normalized to eight decimal places.
  /// @param underlyingToken Address of the underlying token
  /// @param oracleFeed Address of the oracle feed
  /// @return answer uint256, decimals uint8
  function priceFeed(
                     IERC20 underlyingToken,
                     address oracleFeed
                     ) external view returns(uint256, uint8);
  
  /// @notice Get the address of the `QAdmin` contract
  /// @return address Address of `QAdmin` contract
  function qAdmin() external view returns(address);

  /// @notice Get grace period for specified IERC20 token
  /// @return uint Grace period for specified IERC20 token, measured in seconds
  function gracePeriod(address tokenAddress) external view returns(uint);
}

