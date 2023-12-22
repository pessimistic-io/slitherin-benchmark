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
 *    IntentTarget01.sol :: 0xd313e04a4bd954e33c6daabd7f1b277b8087a948
 *    etherscan.io verified 2023-12-01
 */ 
import "./IntentBase.sol";
import "./ProxyReentrancyGuard.sol";

error BadIntentIndex();
error UnsignedCallRequired();

/// @param segmentTarget Contract address where segment functions will be executed
/// @param intents Array of allowed intents
/// @param beforeCalls Array of segment calls to execute before intent execution
/// @param afterCalls Array of segment calls to execute after intent execution
struct Declaration {
  address segmentTarget;
  Intent[] intents;
  bytes[] beforeCalls;
  bytes[] afterCalls;
}

struct Intent {
  Segment[] segments;
}

struct Segment {
  bytes data;
  bool requiresUnsignedCall;
}

struct UnsignedData {
  uint8 intentIndex;
  bytes[] calls;
}

contract IntentTarget01 is IntentBase, ProxyReentrancyGuard {

  /// @dev Execute a signed declaration of intents
  /// @notice This should be executed by metaDelegateCall() or metaDelegateCall_EIP1271() with the following signed and unsigned params
  /// @param declaration Declaration of intents signed by owner [signed]
  /// @param unsignedData Unsigned calldata [unsigned]
  function execute(
    Declaration calldata declaration,
    UnsignedData calldata unsignedData
  ) external nonReentrant {
    if (unsignedData.intentIndex >= declaration.intents.length) {
      revert BadIntentIndex();
    }

    _delegateCallsWithRevert(declaration.segmentTarget, declaration.beforeCalls);

    uint8 nextUnsignedCall = 0;
    for (uint8 i = 0; i < declaration.intents[unsignedData.intentIndex].segments.length; i++) {
      Segment calldata segment = declaration.intents[unsignedData.intentIndex].segments[i];
      bytes memory segmentCallData;
      if (segment.requiresUnsignedCall) {
        if (nextUnsignedCall >= unsignedData.calls.length) {
          revert UnsignedCallRequired();
        }

        bytes memory signedData = segment.data;

        // change length of signedData to ignore the last bytes32
        assembly {
          mstore(add(signedData, 0x0), sub(mload(signedData), 0x20))
        }

        // concat signed and unsigned call bytes
        segmentCallData = bytes.concat(signedData, unsignedData.calls[nextUnsignedCall]);
        nextUnsignedCall++;
      } else {
        segmentCallData = segment.data;
      }
      _delegateCallWithRevert(Call({
        targetContract: declaration.segmentTarget,
        data: segmentCallData
      }));
    }

    _delegateCallsWithRevert(declaration.segmentTarget, declaration.afterCalls);
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

