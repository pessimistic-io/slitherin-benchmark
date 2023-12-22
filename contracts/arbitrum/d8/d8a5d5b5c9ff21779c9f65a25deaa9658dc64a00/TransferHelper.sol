// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library TransferHelper {
  function safeApprove(address token, address to, uint256 value) internal {
    (bool success, bytes memory data) = token.call(abi.encodeWithSignature("approve(address,uint256)", to, value));
    require(success && (data.length == 0 || abi.decode(data, (bool))), "TransferHelper: approve failed");
  }

  function safeTransfer(address token, address to, uint256 value) internal {
    (bool success, bytes memory data) = token.call(abi.encodeWithSignature("transfer(address,uint256)", to, value));
    require(success && (data.length == 0 || abi.decode(data, (bool))), "TransferHelper: transfer failed");
  }

  function safeTransferFrom(address token, address from, address to, uint256 value) internal {
    (bool success, bytes memory data) =
      token.call(abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, value));
    require(success && (data.length == 0 || abi.decode(data, (bool))), "TransferHelper: transferFrom failed");
  }

  function safeTransferETH(address to, uint256 value) internal {
    (bool success,) = to.call{value: value}(new bytes(0));
    require(success, "TransferHelper: ETH transfer failed");
  }
}


