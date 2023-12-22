// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.4;

import "./PriceFeedWithoutRounds.sol";

contract PriceFeedVoltzArbSofrEffectiveDate is PriceFeedWithoutRounds {
  function getDataFeedId() public view virtual override returns (bytes32) {
    return bytes32("SOFR_EFFECTIVE_DATE");
  }

  function getPriceFeedAdapter() public view virtual override returns (IRedstoneAdapter) {
    return IRedstoneAdapter(0x58EBEc7C7BB905E998860942EECF93a4fC90EeA2);
  }
}

