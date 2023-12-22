// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.4;

import "./PriceFeedWithRounds.sol";

contract PriceFeedArbitrumPremiaTwap60WithRounds is PriceFeedWithRounds {
  function getDataFeedId() public view virtual override returns (bytes32) {
    return bytes32("PREMIA-TWAP-60");
  }

  function getPriceFeedAdapter() public view virtual override returns (IRedstoneAdapter) {
    return IRedstoneAdapter(0x5B0E8F9B1A0De4fEC0fbe53387817f30D7Dec800);
  }

  function description() public view virtual override returns (string memory) {
    return "PREMIA / USD";
  }

  function aggregator() external view virtual returns (address) {
    return 0x5B0E8F9B1A0De4fEC0fbe53387817f30D7Dec800;
  }
}

