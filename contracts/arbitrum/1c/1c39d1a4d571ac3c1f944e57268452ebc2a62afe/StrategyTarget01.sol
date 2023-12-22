// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.17;


/**
 *    ,,                           ,,                                
 *   *MM                           db                      `7MM      
 *    MM                                                     MM      
 *    MM,dMMb.      `7Mb,od8     `7MM      `7MMpMMMb.        MM  ,MP'
 *    MM    `Mb       MM' "'       MM        MM    MM        MM ;Y   
 *    MM     M8       MM           MM        MM    MM        MM;Mm   
 *    MM.   ,M9       MM           MM        MM    MM        MM `Mb. 
 *    P^YbmdP'      .JMML.       .JMML.    .JMML  JMML.    .JMML. YA.
 *
 *    StrategyTarget01.sol :: 0x1c39d1a4d571ac3c1f944e57268452ebc2a62afe
 *    etherscan.io verified 2023-11-30
 */ 
import "./StrategyBase.sol";
import "./ProxyReentrancyGuard.sol";

error BadOrderIndex();
error UnsignedCallRequired();

/// @param primitiveTarget Contract address where primitive functions will be executed
/// @param orders Array of allowed orders
/// @param beforeCalls Array of primitive calls to execute before order execution
/// @param afterCalls Array of primitive calls to execute after order execution
struct Strategy {
  address primitiveTarget;
  Order[] orders;
  bytes[] beforeCalls;
  bytes[] afterCalls;
}

struct Order {
  Primitive[] primitives;
}

struct Primitive {
  bytes data;
  bool requiresUnsignedCall;
}

struct UnsignedData {
  uint8 orderIndex;
  bytes[] calls;
}

contract StrategyTarget01 is StrategyBase, ProxyReentrancyGuard {

  /// @dev Execute an order within a signed array of orders
  /// @notice This should be executed by metaDelegateCall() or metaDelegateCall_EIP1271() with the following signed and unsigned params
  /// @param strategy Strategy signed by owner [signed]
  /// @param unsignedData Unsigned calldata [unsigned]
  function execute(
    Strategy calldata strategy,
    UnsignedData calldata unsignedData
  ) external nonReentrant {
    if (unsignedData.orderIndex >= strategy.orders.length) {
      revert BadOrderIndex();
    }

    _delegateCallsWithRevert(strategy.primitiveTarget, strategy.beforeCalls);

    uint8 nextUnsignedCall = 0;
    for (uint8 i = 0; i < strategy.orders[unsignedData.orderIndex].primitives.length; i++) {
      Primitive calldata primitive = strategy.orders[unsignedData.orderIndex].primitives[i];
      bytes memory primitiveCallData;
      if (primitive.requiresUnsignedCall) {
        if (nextUnsignedCall >= unsignedData.calls.length) {
          revert UnsignedCallRequired();
        }

        bytes memory signedData = primitive.data;

        // change length of signedData to ignore the last bytes32
        assembly {
          mstore(add(signedData, 0x0), sub(mload(signedData), 0x20))
        }

        // concat signed and unsigned call bytes
        primitiveCallData = bytes.concat(signedData, unsignedData.calls[nextUnsignedCall]);
        nextUnsignedCall++;
      } else {
        primitiveCallData = primitive.data;
      }
      _delegateCallWithRevert(Call({
        targetContract: strategy.primitiveTarget,
        data: primitiveCallData
      }));
    }

    _delegateCallsWithRevert(strategy.primitiveTarget, strategy.afterCalls);
  }

  function _delegateCallsWithRevert (address targetContract, bytes[] calldata calls) internal {
    for (uint8 i = 0; i < calls.length; i++) {
      _delegateCallWithRevert(Call({
        targetContract: targetContract,
        data: calls[i]
      }));
    }
  }

  function _delegateCallWithRevert (Call memory call) internal {
    address targetContract = call.targetContract;
    bytes memory data = call.data;
    assembly {
      let result := delegatecall(gas(), targetContract, add(data, 0x20), mload(data), 0, 0)
      if eq(result, 0) {
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
      }
    }
  }
}

