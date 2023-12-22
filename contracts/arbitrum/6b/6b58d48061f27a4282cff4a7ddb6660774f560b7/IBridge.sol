// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.17;

import {StargateSettings, WormholeBridgeSettings} from "./LibMagpieAggregator.sol";
import {BridgeInArgs, BridgeOutArgs} from "./data-transfer_LibCommon.sol";

interface IBridge {
    event UpdateStargateSettings(address indexed sender, StargateSettings stargateSettings);

    function updateStargateSettings(StargateSettings calldata stargateSettings) external;

    event UpdateWormholeBridgeSettings(address indexed sender, WormholeBridgeSettings wormholeBridgeSettings);

    function updateWormholeBridgeSettings(WormholeBridgeSettings calldata wormholeBridgeSettings) external;

    event AddMagpieStargateBridgeAddresses(
        address indexed sender,
        uint16[] networkIds,
        bytes32[] magpieStargateBridgeAddresses
    );

    function addMagpieStargateBridgeAddresses(
        uint16[] calldata networkIds,
        bytes32[] calldata magpieStargateBridgeAddresses
    ) external;

    function bridgeIn(BridgeInArgs calldata bridgeInArgs) external payable;

    function bridgeOut(BridgeOutArgs calldata bridgeOutArgs) external payable returns (uint256 amount);
}

