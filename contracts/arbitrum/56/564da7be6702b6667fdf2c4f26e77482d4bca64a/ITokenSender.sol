// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import {IUintValue} from "./IUintValue.sol";
import {IERC20} from "./IERC20.sol";

interface ITokenSender {
  event PriceLowerBoundChange(uint256 price);
  event PriceOracleChange(IUintValue oracle);

  function send(address recipient, uint256 inputAmount) external;

  function setPriceOracle(IUintValue priceOracle) external;

  function setPriceLowerBound(uint256 priceLowerBound) external;

  function getOutputToken() external view returns (IERC20);

  function getPriceOracle() external view returns (IUintValue);

  function getPriceLowerBound() external view returns (uint256);

  function SET_PRICE_ORACLE_ROLE() external view returns (bytes32);

  function SET_PRICE_LOWER_BOUND_ROLE() external view returns (bytes32);

  function SET_ALLOWED_MSG_SENDERS_ROLE() external view returns (bytes32);

  function SET_ACCOUNT_LIMIT_RESET_PERIOD_ROLE()
    external
    view
    returns (bytes32);

  function SET_ACCOUNT_LIMIT_PER_PERIOD_ROLE() external view returns (bytes32);

  function WITHDRAW_ERC20_ROLE() external view returns (bytes32);
}

