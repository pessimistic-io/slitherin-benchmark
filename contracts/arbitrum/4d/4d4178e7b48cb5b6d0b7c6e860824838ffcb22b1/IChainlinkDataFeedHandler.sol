// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IHandler} from "./IHandler.sol";

interface IChainlinkDataFeedHandler is IHandler {
    function whitelistingFee() external returns (uint256);
    function chargeWhitelistingFee() external returns (bool);
    function encodePayload(string calldata dataFeedName) view external returns (bytes memory payload);
}
