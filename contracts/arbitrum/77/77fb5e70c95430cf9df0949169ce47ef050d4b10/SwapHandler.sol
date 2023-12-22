// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.6;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Storage.sol";
import {IRouter as IExchange} from "./IRouter.sol";
import "./Router.sol";
import "./IHandler.sol";

contract SmartTradeSwapHandler is IHandler {
  using SafeERC20 for IERC20;

  struct OrderData {
    address exchange;
    uint256 amountIn;
    address[] path;
    uint256[] amountOutMin;
  }

  struct Options {
    uint8 route;
    uint256 amountOutMin;
    uint256 deadline;
    bool emergency;
  }

  address public router;

  constructor(address _router) {
    require(_router != address(0), "SmartTradeSwapHandler::constructor: invalid router contract address");
    router = _router;
  }

  modifier onlyRouter() {
    require(msg.sender == router, "SmartTradeSwapHandler::onlyRouter: caller is not the router");
    _;
  }

  function callDataEncode(OrderData calldata data) external pure returns (bytes memory) {
    return abi.encode(data);
  }

  function callOptionsEncode(Options calldata data) external pure returns (bytes memory) {
    return abi.encode(data);
  }

  function onOrderCreated(SmartTradeRouter.Order calldata order) external view override onlyRouter {
    abi.decode(order.callData, (OrderData));
  }

  function _returnRemainder(SmartTradeRouter.Order calldata order, address[] memory tokens) internal {
    address _router = router; // gas optimization
    uint256[] memory amounts = new uint256[](tokens.length);
    for (uint256 i = 0; i < tokens.length; i++) {
      amounts[i] = IERC20(tokens[i]).balanceOf(address(this));
      if (amounts[i] == 0) continue;
      IERC20(tokens[i]).safeApprove(_router, amounts[i]);
    }
    SmartTradeRouter(_router).deposit(order.id, tokens, amounts);
  }

  function _swap(
    SmartTradeRouter.Order calldata order,
    OrderData memory data,
    uint256 amountOutMin,
    uint256 deadline
  ) internal {
    address[] memory refundTokens = new address[](1);
    refundTokens[0] = data.path[0];
    uint256[] memory refundAmounts = new uint256[](1);
    refundAmounts[0] = data.amountIn;
    SmartTradeRouter(router).refund(order.id, refundTokens, refundAmounts, address(this));
    IERC20(data.path[0]).safeApprove(data.exchange, data.amountIn);
    IExchange(data.exchange).swapExactTokensForTokensSupportingFeeOnTransferTokens(
      data.amountIn,
      amountOutMin,
      data.path,
      address(this),
      deadline
    );
    _returnRemainder(order, data.path);
  }

  function handle(SmartTradeRouter.Order calldata order, bytes calldata _options) external override onlyRouter {
    OrderData memory data = abi.decode(order.callData, (OrderData));
    Options memory options = abi.decode(_options, (Options));

    if (options.emergency) {
      _swap(order, data, 0, options.deadline);
      return;
    }

    uint256 amountOutMin = options.amountOutMin > 0 ? options.amountOutMin : data.amountOutMin[options.route];
    require(
      data.amountOutMin[options.route] <= amountOutMin,
      "SmartTradeSwapHandler::handle: invalid amount out min option"
    );
    _swap(order, data, amountOutMin, options.deadline);
  }
}

