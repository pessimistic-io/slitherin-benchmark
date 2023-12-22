// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.4;

import "./PriceFeedsAdapterWithRounds.sol";
import "./SafeCast.sol";

contract PriceFeedsAdapterArbitrumPremiaWithRounds is PriceFeedsAdapterWithRounds {

  bytes32 constant private PREMIA_TWAP_60_ID = bytes32("PREMIA-TWAP-60");

  error UpdaterNotAuthorised(address signer);
  error CannotUpdateMoreThanOneDataFeed();

  event AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 updatedAt);

  function getDataFeedIds() public pure override returns (bytes32[] memory dataFeedIds) {
    dataFeedIds = new bytes32[](1);
    dataFeedIds[0] = PREMIA_TWAP_60_ID;
  }

  function getUniqueSignersThreshold() public view virtual override returns (uint8) {
    return 2;
  }

  function requireAuthorisedUpdater(address updater) public view override virtual {
    if (updater != 0x54D1E71a45266A1baFA417d501315c4E8E947b2f) {
      revert UpdaterNotAuthorised(updater);
    }
  }

  function getDataFeedIndex(bytes32 dataFeedId) public view override virtual returns (uint256) {
    if (dataFeedId == PREMIA_TWAP_60_ID) { return 0; }
    revert DataFeedIdNotFound(dataFeedId);
  }

  function getAuthorisedSignerIndex(
    address signerAddress
  ) public view virtual override returns (uint8) {
    if (signerAddress == 0x8BB8F32Df04c8b654987DAaeD53D6B6091e3B774) { return 0; }
    else if (signerAddress == 0xdEB22f54738d54976C4c0fe5ce6d408E40d88499) { return 1; }
    else if (signerAddress == 0x51Ce04Be4b3E32572C4Ec9135221d0691Ba7d202) { return 2; }
    else if (signerAddress == 0xDD682daEC5A90dD295d14DA4b0bec9281017b5bE) { return 3; }
    else if (signerAddress == 0x9c5AE89C4Af6aA32cE58588DBaF90d18a855B6de) { return 4; }
    else {
      revert SignerNotAuthorised(signerAddress);
    }
  }

  function validateAndUpdateDataFeedsValues(
    bytes32[] memory dataFeedsIdsArray,
    uint256[] memory values
  ) internal virtual override {
    if (dataFeedsIdsArray.length != 1 || values.length != 1) {
      revert CannotUpdateMoreThanOneDataFeed();
    }
    _updateDataFeedValue(dataFeedsIdsArray[0], values[0]);
    emit AnswerUpdated(SafeCast.toInt256(values[0]), getLatestRoundId(), getDataTimestampFromLatestUpdate());
  }
}

