// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "./IExternalBribeFactory.sol";
import "./ExternalBribe.sol";

contract ExternalBribeFactory is IExternalBribeFactory {
    address public last_external_bribe;

    function createExternalBribe(address voter, address[] memory allowedRewards) external returns (address) {
        last_external_bribe = address(new ExternalBribe(voter, msg.sender, allowedRewards));
        return last_external_bribe;
    }
}

