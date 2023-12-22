// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./PoolMetadata.sol";
import "./PoolRewards.sol";
import "./PoolConfiguration.sol";
import "./PoolDID.sol";
import {ERC20Upgradeable, IERC20Upgradeable} from "./ERC20Upgradeable.sol";

/// @notice This is perimary protocol contract, describing borrowing Pool
contract PoolMaster is PoolRewards, PoolConfiguration, PoolMetadata, PoolDID {
  // CONSTRUCTOR
  using Decimal for uint256;

  /// @notice Upgradeable contract constructor
  /// @param manager_ Address of the Pool's manager
  /// @param currency_ Address of the currency token
  /// @param requireKYC Flag to enable KYC middleware for pool actions
  function initialize(
    address manager_,
    IERC20Upgradeable currency_,
    bool requireKYC
  ) public initializer {
    __PoolBaseInfo_init(manager_, currency_);
    kycRequired = requireKYC;

    // add provisional repayment utilization
    provisionalRepaymentUtilization = factory.provisionalRepaymentUtilization();
  }

  // VERSION

  function version() external pure virtual returns (string memory) {
    return '1.1.0';
  }

  // OVERRIDES

  /// @notice Override of the mint function, see {IERC20-_mint}
  function _mint(address account, uint256 amount) internal override(ERC20Upgradeable, PoolRewards) {
    super._mint(account, amount);
  }

  /// @notice Override of the mint function, see {IERC20-_burn}
  function _burn(address account, uint256 amount) internal override(ERC20Upgradeable, PoolRewards) {
    super._burn(account, amount);
  }

  /// @notice Override of the transfer function, see {IERC20-_transfer}
  function _transfer(
    address from,
    address to,
    uint256 amount
  ) internal override(ERC20Upgradeable, PoolRewards) {
    super._transfer(from, to, amount);
  }

  /// @notice Override of the decimals function, see {IERC20Metadata-decimals}
  /// @return Cp-token decimals
  function decimals() public view override(ERC20Upgradeable, PoolMetadata) returns (uint8) {
    return super.decimals();
  }

  /// @notice Override of the decimals function, see {IERC20Metadata-symbol}
  /// @return Pool's symbol
  function symbol() public view override(ERC20Upgradeable, PoolMetadata) returns (string memory) {
    return super.symbol();
  }

  function _handleMaxCapacity(uint256 currencyAmount) internal view override {
    if (maximumCapacity != 0) {
      require(currencyAmount + cash() <= maximumCapacity, 'CPM');
    }
  }

  function _utilizationIsBelowProvisionalRepayment() internal view override returns (bool) {
    return _info.borrows < _poolSize(_info).mulDecimal(provisionalRepaymentUtilization);
  }
}

