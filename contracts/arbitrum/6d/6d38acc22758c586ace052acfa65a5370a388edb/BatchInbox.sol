//SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

// import "hardhat/console.sol";

import "./DecompressorExtension.sol";

interface Forwarder {
  struct ForwardRequest {
    address from;
    address to;
    address feeToken;
    uint256 value;
    uint256 gas;
    uint256 nonce;
    uint256 validUntilTime;
    bytes data;
  }

  function getFeeSetting() external view returns (uint256, uint256, uint256, uint256);
  function execute(ForwardRequest calldata req, bytes calldata sig) external payable returns (bool success, bytes memory returnData);
}

contract BatchInbox is DecompressorExtension {

  address forwarderAdderss;

  uint256 minGasUsed;

  // events
  event ForwarderReverted(address indexed from, address to, uint256 nonce, string errorMsg);

  constructor(address _forwarder) {
    forwarderAdderss = _forwarder;
    (, , , minGasUsed) = Forwarder(forwarderAdderss).getFeeSetting();
  }

  fallback() external {
    bytes1 selector = bytes1(msg.data[0:1]);
    bytes memory data = _decompressed(msg.data[1:]);

    // executeBatch
    if (selector == 0x01) {
      (Forwarder.ForwardRequest[] memory reqs, bytes[] memory sigs) = abi.decode(data, (Forwarder.ForwardRequest[], bytes[]));
      executeBatch(reqs, sigs);
    }
  }

  function executeBatch(
    Forwarder.ForwardRequest[] memory reqs,
    bytes[] memory sigs
  ) public payable {
    require(reqs.length == sigs.length, "BatchInbox: number of requests does not match number of signatures");

    uint256 count = reqs.length;
    for (uint i = 0; i < count; i++) {
      try Forwarder(forwarderAdderss).execute{gas: reqs[i].gas + minGasUsed, value: reqs[i].value}(reqs[i], sigs[i]) returns (bool success, bytes memory returnData) {
        if (!success) emit ForwarderReverted(reqs[i].from, reqs[i].to, reqs[i].nonce, string(returnData));
      } catch Error(string memory reason) {
        emit ForwarderReverted(reqs[i].from, reqs[i].to, reqs[i].nonce, reason);
      }
    }
  }
  
  function setForwarder(address _forwarder) external onlyOwner {
    forwarderAdderss = _forwarder;
    (, , , minGasUsed) = Forwarder(forwarderAdderss).getFeeSetting();
  }
}

