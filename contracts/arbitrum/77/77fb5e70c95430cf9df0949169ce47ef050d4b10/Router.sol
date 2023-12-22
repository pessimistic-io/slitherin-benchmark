// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.6;

import "./Ownable.sol";
import "./Pausable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./AggregatorV3Interface.sol";
import "./Storage.sol";
import "./Balance.sol";
import "./IHandler.sol";

contract SmartTradeRouter is Ownable, Pausable {
  using SafeERC20 for IERC20;

  enum OrderStatus {
    Pending,
    Succeeded,
    Canceled
  }

  struct Order {
    uint256 id;
    address owner;
    OrderStatus status;
    address handler;
    bytes callData;
  }

  /// @notice Storage contract
  Storage public info;

  mapping(uint256 => Order) internal _orders;

  mapping(uint256 => mapping(address => uint256)) internal _orderBalances;

  uint256 public ordersCount;

  event StorageChanged(address indexed info);

  event HandlerAdded(address indexed handler);

  event HandlerRemoved(address indexed handler);

  event OrderCreated(uint256 indexed id, address indexed owner, address indexed handler);

  event OrderUpdated(uint256 indexed id);

  event OrderCanceled(uint256 indexed id);

  event OrderSuccessed(uint256 indexed id);

  constructor(address _info) {
    require(_info != address(0), "SmartTradeRouter::constructor: invalid storage contract address");

    info = Storage(_info);
  }

  function pause() external {
    address pauser = info.getAddress(keccak256("DFH:Pauser"));
    require(
      msg.sender == owner() || msg.sender == pauser,
      "SmartTradeRouter::pause: caller is not the owner or pauser"
    );
    _pause();
  }

  function unpause() external {
    address pauser = info.getAddress(keccak256("DFH:Pauser"));
    require(
      msg.sender == owner() || msg.sender == pauser,
      "SmartTradeRouter::unpause: caller is not the owner or pauser"
    );
    _unpause();
  }

  /**
   * @notice Change storage contract address.
   * @param _info New storage contract address.
   */
  function changeStorage(address _info) external onlyOwner {
    require(_info != address(0), "SmartTradeRouter::changeStorage: invalid storage contract address");

    info = Storage(_info);
    emit StorageChanged(_info);
  }

  /**
   * @return Current protocol commission.
   */
  function fee() public view returns (uint256) {
    uint256 feeUSD = info.getUint(keccak256("DFH:Fee:Automate:SmartTrade"));
    if (feeUSD == 0) return 0;

    (, int256 answer, , , ) = AggregatorV3Interface(info.getAddress(keccak256("DFH:Fee:PriceFeed"))).latestRoundData();
    require(answer > 0, "SmartTradeRouter::fee: invalid price feed response");

    return (feeUSD * 1e18) / uint256(answer);
  }

  function balanceOf(uint256 orderId, address token) public view returns (uint256) {
    return _orderBalances[orderId][token];
  }

  function deposit(
    uint256 orderId,
    address[] calldata tokens,
    uint256[] calldata amounts
  ) public whenNotPaused {
    require(_orders[orderId].owner != address(0), "SmartTradeRouter::deposit: undefined order");
    require(
      msg.sender == _orders[orderId].owner ||
        info.getBool(keccak256(abi.encodePacked("DFH:Contract:SmartTrade:allowedHandler:", msg.sender))),
      "SmartTradeRouter::deposit: foreign order"
    );
    require(tokens.length == amounts.length, "SmartTradeRouter::deposit: invalid amounts length");

    for (uint256 i = 0; i < tokens.length; i++) {
      require(tokens[i] != address(0), "SmartTradeRouter::deposit: invalid token contract address");
      if (amounts[i] == 0) continue;

      IERC20(tokens[i]).safeTransferFrom(msg.sender, address(this), amounts[i]);
      _orderBalances[orderId][tokens[i]] += amounts[i];
    }
  }

  function refund(
    uint256 orderId,
    address[] calldata tokens,
    uint256[] memory amounts,
    address recipient
  ) public whenNotPaused {
    require(
      msg.sender == _orders[orderId].owner ||
        msg.sender == owner() ||
        info.getBool(keccak256(abi.encodePacked("DFH:Contract:SmartTrade:allowedHandler:", msg.sender))),
      "SmartTradeRouter::refund: foreign order"
    );
    require(tokens.length == amounts.length, "SmartTradeRouter::refund: invalid amounts length");

    for (uint256 i = 0; i < tokens.length; i++) {
      require(tokens[i] != address(0), "SmartTradeRouter::refund: invalid token contract address");
      if (amounts[i] == 0) continue;
      require(balanceOf(orderId, tokens[i]) >= amounts[i], "SmartTradeRouter::refund: insufficient balance");

      _orderBalances[orderId][tokens[i]] -= amounts[i];
      IERC20(tokens[i]).safeTransfer(recipient, amounts[i]);
    }
  }

  function order(uint256 id) public view returns (Order memory) {
    return _orders[id];
  }

  function createOrder(
    address handler,
    bytes calldata callData,
    address[] calldata tokens,
    uint256[] calldata amounts
  ) external payable whenNotPaused returns (uint256) {
    require(
      info.getBool(keccak256(abi.encodePacked("DFH:Contract:SmartTrade:allowedHandler:", handler))),
      "SmartTradeRouter::createOrder: invalid handler address"
    );

    ordersCount++;
    Order storage newOrder = _orders[ordersCount];
    newOrder.id = ordersCount;
    newOrder.owner = msg.sender;
    newOrder.status = OrderStatus.Pending;
    newOrder.handler = handler;
    newOrder.callData = callData;
    emit OrderCreated(newOrder.id, newOrder.owner, newOrder.handler);
    IHandler(newOrder.handler).onOrderCreated(newOrder);

    if (tokens.length > 0) {
      deposit(newOrder.id, tokens, amounts);
    }

    if (msg.value > 0) {
      address balance = info.getAddress(keccak256("DFH:Contract:Balance"));
      require(balance != address(0), "SmartTradeRouter::createOrder: invalid balance contract address");

      Balance(balance).deposit{value: msg.value}(newOrder.owner);
    }

    return newOrder.id;
  }

  function updateOrder(uint256 id, bytes calldata callData) external whenNotPaused {
    Order storage _order = _orders[id];
    require(_order.owner != address(0), "SmartTradeRouter::updateOrder: undefined order");
    require(msg.sender == _order.owner || msg.sender == owner(), "SmartTradeRouter::updateOrder: forbidden");
    require(_order.status == OrderStatus.Pending, "SmartTradeRouter::updateOrder: order has already been processed");

    _order.callData = callData;
    emit OrderUpdated(id);
  }

  function cancelOrder(uint256 id, address[] calldata refundTokens) external {
    Order storage _order = _orders[id];
    require(_order.owner != address(0), "SmartTradeRouter::cancelOrder: undefined order");
    require(msg.sender == _order.owner || msg.sender == owner(), "SmartTradeRouter::cancelOrder: forbidden");
    require(_order.status == OrderStatus.Pending, "SmartTradeRouter::cancelOrder: order has already been processed");

    _order.status = OrderStatus.Canceled;
    emit OrderCanceled(_order.id);

    uint256[] memory refundAmounts = new uint256[](refundTokens.length);
    for (uint256 i = 0; i < refundTokens.length; i++) {
      refundAmounts[i] = _orderBalances[id][refundTokens[i]];
    }
    refund(id, refundTokens, refundAmounts, _order.owner);
  }

  function handleOrder(
    uint256 id,
    bytes calldata options,
    uint256 gasFee
  ) external whenNotPaused {
    Order storage _order = _orders[id];
    require(_order.owner != address(0), "SmartTradeRouter::handleOrder: undefined order");
    require(_order.status == OrderStatus.Pending, "SmartTradeRouter::handleOrder: order has already been processed");

    // solhint-disable-next-line avoid-tx-origin
    if (tx.origin != _order.owner) {
      address balance = info.getAddress(keccak256("DFH:Contract:Balance"));
      require(balance != address(0), "SmartTradeRouter::handleOrder: invalid balance contract address");
      Balance(balance).claim(_order.owner, gasFee, fee(), "SmartTradeHandle");
    }

    IHandler(_order.handler).handle(_order, options);
    _order.status = OrderStatus.Succeeded;
    emit OrderSuccessed(id);
  }
}

