// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IPolicyManager} from "./IPolicyManager.sol";

interface IPolicy {
    function addTradeSettings(
        address _fundManager,
        bytes calldata _encodedSettings
    ) external;

    function canDisable() external pure returns (bool canDisable_);

    function implementedHooks()
        external
        pure
        returns (IPolicyManager.PolicyHook[] memory implementedHooks_);

    function updateTradeSettings(
        address _fundManager,
        bytes calldata _encodedSettings
    ) external;

    function validateRule(
        address _fundManagers,
        IPolicyManager.PolicyHook _hook,
        bytes calldata _encodedArgs
    ) external returns (bool isValid_, bytes memory message);

    function getTradeSettings(
        address _fundManager
    ) external view returns (bytes memory);

    function identifier() external view returns (string memory);
}

