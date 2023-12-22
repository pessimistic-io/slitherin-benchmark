// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {IStrategyMessages} from "./IStrategyMessages.sol";

interface ISimpleVault is IStrategyMessages {
    function onChainReport(
        uint16 _chainId,
        StrategyReport memory _message,
        uint256 _receivedTokens
    ) external;
}

