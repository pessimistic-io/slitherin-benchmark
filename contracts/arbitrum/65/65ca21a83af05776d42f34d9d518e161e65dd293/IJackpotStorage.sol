// SPDX-License-Identifier: Business Source License 1.1
pragma solidity ^0.8.19;

import "./ProbabilityType.sol";

abstract contract IJackpotStorage {
    function _jackpot(address token) internal virtual view returns (uint);
    function _addJackpot(address token, int amount) internal virtual;
    function _listJackpots() internal virtual view returns (address[] storage);
    function _jackpotShare() internal virtual view returns (Probability);
}
