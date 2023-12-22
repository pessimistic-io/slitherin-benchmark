// Solidity files have to start with this pragma.
// It will be used by the Solidity compiler to validate its version.
pragma solidity ^0.8.0;

struct TeleportGUID {
  bytes32 sourceDomain;
  bytes32 targetDomain;
  bytes32 receiver;
  bytes32 operator;
  uint128 amount;
  uint80 nonce;
  uint48 timestamp;
}

contract TeleportEventSim {
  event TeleportInitialized(TeleportGUID wormhole);

  uint80 nonce;

  function emitRandomEvent() external {
    nonce++;
    uint256 seed = block.timestamp + nonce;

    TeleportGUID memory wormhole = TeleportGUID({
      sourceDomain: keccak256(abi.encodePacked(seed+1)),
      targetDomain: keccak256(abi.encodePacked(seed+2)),
      receiver: bytes32(bytes20(keccak256(abi.encodePacked(seed+3)))),
      operator: bytes32(bytes20(keccak256(abi.encodePacked(seed+4)))),
      amount: uint128(bytes16(keccak256(abi.encodePacked(seed+5)))),
      nonce: nonce,
      timestamp: uint48(block.timestamp)
    });

    emit TeleportInitialized(wormhole);
  }

  function emitRandomEvents(int n) external {
    for (int i = 0; i < n; i++) {
      nonce++;
      uint256 seed = block.timestamp + nonce;

      TeleportGUID memory wormhole = TeleportGUID({
      sourceDomain: keccak256(abi.encodePacked(seed+1)),
      targetDomain: keccak256(abi.encodePacked(seed+2)),
      receiver: bytes32(bytes20(keccak256(abi.encodePacked(seed+3)))),
      operator: bytes32(bytes20(keccak256(abi.encodePacked(seed+4)))),
      amount: uint128(bytes16(keccak256(abi.encodePacked(seed+5)))),
      nonce: nonce,
      timestamp: uint48(block.timestamp)
      });

      emit TeleportInitialized(wormhole);
    }
  }
}