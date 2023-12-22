// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "./Bribe.sol";
import "./IBribeFactory.sol";

contract BribeFactory is IBribeFactory {
    address public lastGauge;

    event BribeCreated(address value);

    function createBribe(address[] memory _allowedRewardTokens) external override returns (address _lastGauge) {
        lastGauge = address(new Bribe(msg.sender, _allowedRewardTokens));
        emit BribeCreated(_lastGauge);
        return lastGauge;
    }
}

