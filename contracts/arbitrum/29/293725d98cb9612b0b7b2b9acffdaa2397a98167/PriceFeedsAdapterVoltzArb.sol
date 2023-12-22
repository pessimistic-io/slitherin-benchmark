// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.4;

import "./PriceFeedsAdapterWithoutRounds.sol";

contract PriceFeedsAdapterVoltzArb is PriceFeedsAdapterWithoutRounds {

  bytes32 constant private SOFR_ID = bytes32("SOFR");
  bytes32 constant private SOFR_EFFECTIVE_DATE_ID = bytes32("SOFR_EFFECTIVE_DATE");
  bytes32 constant private SOFRAI_ID = bytes32("SOFRAI");
  bytes32 constant private SOFRAI_EFFECTIVE_DATE_ID = bytes32("SOFRAI_EFFECTIVE_DATE");

  error UpdaterNotAuthorised(address signer);

  function getDataFeedIds() public pure override returns (bytes32[] memory dataFeedIds) {
    dataFeedIds = new bytes32[](4);
    dataFeedIds[0] = SOFR_ID;
    dataFeedIds[1] = SOFR_EFFECTIVE_DATE_ID;
    dataFeedIds[2] = SOFRAI_ID;
    dataFeedIds[3] = SOFRAI_EFFECTIVE_DATE_ID;
  }

  function getUniqueSignersThreshold() public view virtual override returns (uint8) {
    return 2;
  }

  function requireAuthorisedUpdater(address updater) public view override virtual {
    if (updater != 0xcBb789c8156073283EF69A893E2Dfe06D8F9C655) {
      revert UpdaterNotAuthorised(updater);
    }
  }


  function getDataFeedIndex(bytes32 dataFeedId) public view override virtual returns (uint256) {
    if (dataFeedId == SOFR_ID) { return 0; }
    else if (dataFeedId == SOFR_EFFECTIVE_DATE_ID) { return 1; }
    else if (dataFeedId == SOFRAI_ID) { return 2; }
    else if (dataFeedId == SOFRAI_EFFECTIVE_DATE_ID) { return 3; }
    revert DataFeedIdNotFound(dataFeedId);
  }

  function getAuthorisedSignerIndex(
    address signerAddress
  ) public view virtual override returns (uint8) {
    if (signerAddress == 0x1eA62d73EdF8AC05DfceA1A34b9796E937a29EfF) { return 0; }
    else if (signerAddress == 0x2c59617248994D12816EE1Fa77CE0a64eEB456BF) { return 1; }
    else if (signerAddress == 0x12470f7aBA85c8b81D63137DD5925D6EE114952b) { return 2; }
    else if (signerAddress == 0x109B4a318A4F5ddcbCA6349B45f881B4137deaFB) { return 3; }
    else if (signerAddress == 0x83cbA8c619fb629b81A65C2e67fE15cf3E3C9747) { return 4; }
    else {
      revert SignerNotAuthorised(signerAddress);
    }
  }
}

