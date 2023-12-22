// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import "./ITreasuryCaller.sol";

contract TreasuryCaller is ITreasuryCaller {
  address internal _treasury;

  function setTreasury(address treasury) public virtual override {
    _treasury = treasury;
    emit TreasuryChange(treasury);
  }

  function getTreasury() external view override returns (address) {
    return _treasury;
  }
}

