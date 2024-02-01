// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.5.0;
pragma experimental ABIEncoderV2;

struct PoolAllocationRequest {
  uint40 poolId;
  bool skip;
  uint coverAmountInAsset;
}

struct BuyCoverParams {
  uint coverId;
  address owner;
  uint24 productId;
  uint8 coverAsset;
  uint96 amount;
  uint32 period;
  uint maxPremiumInAsset;
  uint8 paymentAsset;
  uint16 commissionRatio;
  address commissionDestination;
  string ipfsData;
}

interface ICover {

  function buyCover(
    BuyCoverParams calldata params,
    PoolAllocationRequest[] calldata coverChunkRequests
  ) external payable returns (uint coverId);

}

