//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./LibOrder.sol";
import { IERC20 } from "./IERC20.sol";
import { EIP712 } from "./EIP712.sol";
import { SignatureChecker } from "./SignatureChecker.sol";

// import "hardhat/console.sol";

interface IWETH9 {
  function depositTo(address) external payable;

  function withdrawTo(address, uint256) external;

  function balanceOf(address) external view returns (uint256);
}

contract ZigZagExchange is EIP712 {
  event Swap(
    address maker,
    address indexed taker,
    address indexed makerSellToken,
    address indexed takerSellToken,
    uint256 makerSellAmount,
    uint256 takerSellAmount,
    uint256 makerVolumeFee,
    uint256 takerVolumeFee
  );

  event CancelOrder(bytes32 indexed orderHash);
  event OrderStatus(bytes32 indexed orderHash, uint filled, uint remaining);

  mapping(bytes32 => uint256) public filled;

  mapping(bytes32 => bool) public cancelled;

  // fees
  address immutable FEE_ADDRESS;
  address immutable WETH_ADDRESS;
  address immutable EXCHANGE_ADDRESS;
  address constant ETH_ADDRESS = address(0);

  uint256 maker_fee_numerator = 0;
  uint256 maker_fee_denominator = 10000;
  uint256 taker_fee_numerator = 5;
  uint256 taker_fee_denominator = 10000;

  // initialize fee address
  constructor(string memory name, string memory version, address fee_address, address weth_address) EIP712(name, version) {
    FEE_ADDRESS = fee_address;
    WETH_ADDRESS = weth_address;
    EXCHANGE_ADDRESS = address(this);
  }

  receive() external payable {}

  /// @notice Cancel an order so it can no longer be filled
  /// @param order order that should get cancelled
  function cancelOrder(LibOrder.Order calldata order) public {
    require(msg.sender == order.user, 'only user may cancel order');
    bytes32 orderHash = LibOrder.getOrderHash(order);
    require(filled[orderHash] < order.sellAmount, 'order already filled');
    cancelled[orderHash] = true;
    emit CancelOrder(orderHash);
  }

  function fillOrderRouteETH(
    LibOrder.Order[] calldata makerOrder,
    bytes[] calldata makerSignature,
    uint takerAmount,
    bool fillAvailable
  ) public payable returns (bool) {
    require(makerOrder.length == makerSignature.length, 'Length of makerOrders and makerSignatures does not match');
    require(makerOrder.length > 0, 'Length of makerOrders can not be 0');

    if (makerOrder.length == 1) {
      return fillOrderExactInputETH(makerOrder[0], makerSignature[0], takerAmount, fillAvailable);
    }

    uint256 n = makerOrder.length - 1;
    for (uint i = 0; i <= n; i++) {
      require(i == 0 || makerOrder[i - 1].sellToken == makerOrder[i].buyToken, 'Tokens on route do not match');

      // takerAmountOut = takerAmountIn * price
      takerAmount = (takerAmount * makerOrder[i].sellAmount) / makerOrder[i].buyAmount;

      // first or last tx might need to (un-)wrap ETH
      if (i == 0 && makerOrder[0].buyToken == WETH_ADDRESS) {
        _fillOrderETH(makerOrder[0], makerSignature[0], msg.sender, EXCHANGE_ADDRESS, takerAmount, fillAvailable);
      } else if (i == n && makerOrder[n].sellToken == WETH_ADDRESS) {
        _fillOrderETH(makerOrder[n], makerSignature[n], EXCHANGE_ADDRESS, msg.sender, takerAmount, fillAvailable);
      } else {
        _fillOrder(
          makerOrder[i],
          makerSignature[i],
          i == 0 ? msg.sender : EXCHANGE_ADDRESS,
          i == n ? msg.sender : EXCHANGE_ADDRESS,
          makerOrder[i].sellToken,
          makerOrder[i].buyToken,
          takerAmount,
          fillAvailable
        );
      }

      // adjust the takerAmountOut by the tx fee paid by the taker
      takerAmount = takerAmount - (takerAmount * taker_fee_numerator) / taker_fee_denominator;
    }

    _refundETH();
    return true;
  }

  function fillOrderRoute(
    LibOrder.Order[] calldata makerOrder,
    bytes[] calldata makerSignature,
    uint takerAmount,
    bool fillAvailable
  ) public payable returns (bool) {
    require(makerOrder.length == makerSignature.length, 'Length of makerOrders and makerSignatures does not match');
    require(makerOrder.length > 0, 'Length of makerOrders can not be 0');

    if (makerOrder.length == 1) {
      return fillOrderExactInput(makerOrder[0], makerSignature[0], takerAmount, fillAvailable);
    }

    uint256 n = makerOrder.length - 1;
    for (uint i = 0; i <= n; i++) {
      require(i == 0 || makerOrder[i - 1].sellToken == makerOrder[i].buyToken, 'Tokens on route do not match');

      // takerAmountOut = takerAmountIn * price
      takerAmount = (takerAmount * makerOrder[i].sellAmount) / makerOrder[i].buyAmount;

      _fillOrder(
        makerOrder[i],
        makerSignature[i],
        i == 0 ? msg.sender : EXCHANGE_ADDRESS,
        i == n ? msg.sender : EXCHANGE_ADDRESS,
        makerOrder[i].sellToken,
        makerOrder[i].buyToken,
        takerAmount,
        fillAvailable
      );

      // adjust the takerAmountOut by the tx fee paid by the taker
      takerAmount = takerAmount - (takerAmount * taker_fee_numerator) / taker_fee_denominator;
    }

    return true;
  }

  /// @notice Fills an order with an exact amount to sell, taking or returning ETH
  /// @param makerOrder Order that will be used to make this swap, buyToken or sellToken must be WETH
  /// @param makerSignature  Signature for the order used
  /// @param takerSellAmount amount send from the sender to the maker
  /// @return returns true if successfull
  function fillOrderExactInputETH(
    LibOrder.Order calldata makerOrder,
    bytes calldata makerSignature,
    uint takerSellAmount,
    bool fillAvailable
  ) public payable returns (bool) {
    uint takerBuyAmount = (takerSellAmount * makerOrder.sellAmount) / makerOrder.buyAmount;
    _fillOrderETH(makerOrder, makerSignature, msg.sender, msg.sender, takerBuyAmount, fillAvailable);
    _refundETH();
    return true;
  }

  /// @notice Fills an order with an exact amount to buy, taking or returning ETH
  /// @param makerOrder Order that will be used to make this swap, buyToken or sellToken must be WETH
  /// @param makerSignature  Signature for the order used
  /// @param takerBuyAmount amount send to the sender from the maker
  /// @param fillAvailable Should the maximum buyAmount possible be used
  /// @return returns true if successfull
  function fillOrderExactOutputETH(
    LibOrder.Order calldata makerOrder,
    bytes calldata makerSignature,
    uint takerBuyAmount,
    bool fillAvailable
  ) public payable returns (bool) {
    // add the takerFee to the buy amount to recive the exact amount after fees
    takerBuyAmount = (takerBuyAmount * taker_fee_denominator) / (taker_fee_denominator - taker_fee_numerator);
    _fillOrderETH(makerOrder, makerSignature, msg.sender, msg.sender, takerBuyAmount, fillAvailable);
    _refundETH();
    return true;
  }

  function _fillOrderETH(
    LibOrder.Order calldata makerOrder,
    bytes calldata makerSignature,
    address taker,
    address takerReciver,
    uint takerBuyAmountAdjusted,
    bool fillAvailable
  ) internal {
    require(makerOrder.buyToken == WETH_ADDRESS || makerOrder.sellToken == WETH_ADDRESS, 'Either buy or sell token should be WETH');

    if (makerOrder.buyToken == WETH_ADDRESS) {
      _fillOrder(makerOrder, makerSignature, taker, takerReciver, makerOrder.sellToken, ETH_ADDRESS, takerBuyAmountAdjusted, fillAvailable);
    } else {
      _fillOrder(makerOrder, makerSignature, taker, takerReciver, ETH_ADDRESS, makerOrder.buyToken, takerBuyAmountAdjusted, fillAvailable);
    }
  }

  /// @notice Fills an order with an exact amount to sell
  /// @param makerOrder Order that will be used to make this swap
  /// @param makerSignature  Signature for the order used
  /// @param takerSellAmount amount send from the sender to the maker
  /// @return returns true if successfull
  function fillOrderExactInput(
    LibOrder.Order calldata makerOrder,
    bytes calldata makerSignature,
    uint takerSellAmount,
    bool fillAvailable
  ) public returns (bool) {
    uint takerBuyAmount = (takerSellAmount * makerOrder.sellAmount) / makerOrder.buyAmount;
    _fillOrder(
      makerOrder,
      makerSignature,
      msg.sender,
      msg.sender,
      makerOrder.sellToken,
      makerOrder.buyToken,
      takerBuyAmount,
      fillAvailable
    );
    return true;
  }

  /// @notice Fills an order with an exact amount to buy
  /// @param makerOrder Order that will be used to make this swap
  /// @param makerSignature  Signature for the order used
  /// @param takerBuyAmount amount send to the sender from the maker
  /// @param fillAvailable Should the maximum buyAmount possible be used
  /// @return returns true if successfull
  function fillOrderExactOutput(
    LibOrder.Order calldata makerOrder,
    bytes calldata makerSignature,
    uint takerBuyAmount,
    bool fillAvailable
  ) public returns (bool) {
    // add the takerFee to the buy amount to recive the exact amount after fees
    takerBuyAmount = (takerBuyAmount * taker_fee_denominator) / (taker_fee_denominator - taker_fee_numerator);
    _fillOrder(
      makerOrder,
      makerSignature,
      msg.sender,
      msg.sender,
      makerOrder.sellToken,
      makerOrder.buyToken,
      takerBuyAmount,
      fillAvailable
    );
    return true;
  }

  function _fillOrder(
    LibOrder.Order calldata makerOrder,
    bytes calldata makerSignature,
    address taker,
    address takerReciver,
    address sellToken,
    address buyToken,
    uint takerBuyAmountAdjusted,
    bool fillAvailable
  ) internal {
    require(takerReciver != ETH_ADDRESS, "Can't recive to zero address");

    //validate signature
    LibOrder.OrderInfo memory makerOrderInfo = getOpenOrder(makerOrder);
    require(_isValidSignatureHash(makerOrder.user, makerOrderInfo.orderHash, makerSignature), 'invalid maker signature');

    uint takerSellAmount;
    {
      // prevent Stack too deep
      uint availableTakerSellSize = makerOrder.sellAmount - makerOrderInfo.orderSellFilledAmount;
      if (fillAvailable && availableTakerSellSize < takerBuyAmountAdjusted) takerBuyAmountAdjusted = availableTakerSellSize;
      takerSellAmount = (takerBuyAmountAdjusted * makerOrder.buyAmount) / makerOrder.sellAmount;
      require(takerBuyAmountAdjusted <= availableTakerSellSize, 'amount exceeds available size');
    }

    // mark fills in storage
    uint makerOrderFilled = makerOrderInfo.orderSellFilledAmount + takerBuyAmountAdjusted;
    filled[makerOrderInfo.orderHash] = makerOrderFilled;

    // The fee gets subtracted from the buy amounts so they deduct from the total instead of adding on to it
    // The maker fee comes out of the taker sell quantity, so the maker ends up with less
    // The taker fee comes out of the maker sell quantity, so the taker ends up with less
    // makerFee = (takerSellAmount * maker_fee_numerator) / maker_fee_denominator
    // takerFee = (takerBuyAmountAdjusted * taker_fee_numerator) / taker_fee_denominator

    _settleMatchedOrders(
      makerOrder.user,
      taker,
      takerReciver,
      sellToken,
      buyToken,
      takerBuyAmountAdjusted,
      takerSellAmount,
      (takerSellAmount * maker_fee_numerator) / maker_fee_denominator,
      (takerBuyAmountAdjusted * taker_fee_numerator) / taker_fee_denominator
    );

    emit OrderStatus(makerOrderInfo.orderHash, makerOrderFilled, makerOrder.sellAmount - makerOrderFilled);
  }

  function _settleMatchedOrders(
    address maker,
    address taker,
    address takerReciver,
    address makerSellToken,
    address takerSellToken,
    uint makerSellAmount,
    uint takerSellAmount,
    uint makerFee,
    uint takerFee
  ) internal {
    if (takerSellToken == ETH_ADDRESS) {
      require(msg.value >= takerSellAmount, 'msg value not high enough');
    } else if (taker != EXCHANGE_ADDRESS) {
      require(IERC20(takerSellToken).balanceOf(taker) >= takerSellAmount, 'taker order not enough balance');
      require(IERC20(takerSellToken).allowance(taker, EXCHANGE_ADDRESS) >= takerSellAmount, 'taker order not enough allowance');
    }

    if (makerSellToken == ETH_ADDRESS) {
      require(IERC20(WETH_ADDRESS).balanceOf(maker) >= makerSellAmount, 'maker order not enough balance');
      require(IERC20(WETH_ADDRESS).allowance(maker, EXCHANGE_ADDRESS) >= makerSellAmount, 'maker order not enough allowance');
    } else {
      require(IERC20(makerSellToken).balanceOf(maker) >= makerSellAmount, 'maker order not enough balance');
      require(IERC20(makerSellToken).allowance(maker, EXCHANGE_ADDRESS) >= makerSellAmount, 'maker order not enough allowance');
    }

    // Taker fee -> fee recipient
    // taker fee is collected in takerBuyToken
    if (takerFee > 0) {
      if (makerSellToken == ETH_ADDRESS) {
        IERC20(WETH_ADDRESS).transferFrom(maker, FEE_ADDRESS, takerFee);
      } else {
        IERC20(makerSellToken).transferFrom(maker, FEE_ADDRESS, takerFee);
      }
    }

    // Maker fee -> fee recipient
    // Maker fee is collected in makerBuyToken
    if (makerFee > 0) {
      if (takerSellToken == ETH_ADDRESS) {
        IWETH9(WETH_ADDRESS).depositTo{ value: makerFee }(FEE_ADDRESS);
      } else if (taker == EXCHANGE_ADDRESS) {
        IERC20(takerSellToken).transfer(FEE_ADDRESS, makerFee);
      } else {
        IERC20(takerSellToken).transferFrom(taker, FEE_ADDRESS, makerFee);
      }
    }

    // taker -> maker
    if (takerSellToken == ETH_ADDRESS) {
      IWETH9(WETH_ADDRESS).depositTo{ value: takerSellAmount - makerFee }(maker);
    } else if (taker == EXCHANGE_ADDRESS) {
      IERC20(takerSellToken).transfer(maker, takerSellAmount - makerFee);
    } else {
      IERC20(takerSellToken).transferFrom(taker, maker, takerSellAmount - makerFee);
    }

    // maker -> taker
    if (makerSellToken == ETH_ADDRESS) {
      IERC20(WETH_ADDRESS).transferFrom(maker, EXCHANGE_ADDRESS, makerSellAmount - takerFee);
      IWETH9(WETH_ADDRESS).withdrawTo(takerReciver, makerSellAmount - takerFee);
    } else {
      IERC20(makerSellToken).transferFrom(maker, takerReciver, makerSellAmount - takerFee);
    }
    
    emit Swap(maker, taker, makerSellToken, takerSellToken, makerSellAmount, takerSellAmount, makerFee, takerFee);
  }

  function getOpenOrder(LibOrder.Order calldata order) public view returns (LibOrder.OrderInfo memory orderInfo) {
    orderInfo.orderHash = LibOrder.getOrderHash(order);
    orderInfo.orderSellFilledAmount = filled[orderInfo.orderHash];

    require(orderInfo.orderSellFilledAmount < order.sellAmount, 'order is filled');
    require(block.timestamp <= order.expirationTimeSeconds, 'order expired');
    require(!cancelled[orderInfo.orderHash], 'order canceled');
  }

  function isValidOrderSignature(LibOrder.Order calldata order, bytes calldata signature) public view returns (bool) {
    bytes32 orderHash = LibOrder.getOrderHash(order);
    return _isValidSignatureHash(order.user, orderHash, signature);
  }

  // hash can be an order hash or a cancel order hash
  function _isValidSignatureHash(address user, bytes32 hash, bytes calldata signature) private view returns (bool) {
    bytes32 digest = _hashTypedDataV4(hash);
    return SignatureChecker.isValidSignatureNow(user, digest, signature);
  }

  function _refundETH() internal {
    if (address(this).balance > 0) {
      (bool success, ) = msg.sender.call{ value: address(this).balance }(new bytes(0));
      require(success, 'ETH transfer failed');
    }
  }
}

