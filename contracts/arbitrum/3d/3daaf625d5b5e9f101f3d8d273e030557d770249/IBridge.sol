// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IMessageBus} from "./IMessageBus.sol";
import {StargateSettings, WormholeBridgeSettings, CelerBridgeSettings} from "./LibMagpieAggregator.sol";
import {TransferKey} from "./LibTransferKey.sol";
import {BridgeInArgs, BridgeOutArgs, RefundArgs} from "./data-transfer_LibCommon.sol";

interface IBridge {
    event UpdateStargateSettings(address indexed sender, StargateSettings stargateSettings);

    function updateStargateSettings(StargateSettings calldata stargateSettings) external;

    event UpdateWormholeBridgeSettings(address indexed sender, WormholeBridgeSettings wormholeBridgeSettings);

    function updateWormholeBridgeSettings(WormholeBridgeSettings calldata wormholeBridgeSettings) external;

    event AddCelerChainIds(address indexed sender, uint16[] networkIds, uint64[] chainIds);

    function addCelerChainIds(uint16[] calldata networkIds, uint64[] calldata chainIds) external;

    event UpdateCelerBridgeSettings(address indexed sender, CelerBridgeSettings celerBridgeSettings);

    function updateCelerBridgeSettings(CelerBridgeSettings calldata celerBridgeSettings) external;

    event AddMagpieStargateBridgeAddresses(
        address indexed sender,
        uint16[] networkIds,
        bytes32[] magpieStargateBridgeAddresses
    );

    function addMagpieStargateBridgeAddresses(
        uint16[] calldata networkIds,
        bytes32[] calldata magpieStargateBridgeAddresses
    ) external;

    event AddMagpieStargateBridgeV2Addresses(
        address indexed sender,
        uint16[] networkIds,
        bytes32[] magpieStargateBridgeAddresses
    );

    function addMagpieStargateBridgeV2Addresses(
        uint16[] calldata networkIds,
        bytes32[] calldata magpieStargateBridgeAddresses
    ) external;

    event AddMagpieCelerBridgeAddresses(
        address indexed sender,
        uint16[] networkIds,
        bytes32[] magpieCelerBridgeAddresses
    );

    function addMagpieCelerBridgeAddresses(
        uint16[] calldata networkIds,
        bytes32[] calldata magpieCelerBridgeAddresses
    ) external;

    function bridgeIn(BridgeInArgs calldata bridgeInArgs) external payable;

    function bridgeOut(BridgeOutArgs calldata bridgeOutArgs) external payable returns (uint256 amount);
}

