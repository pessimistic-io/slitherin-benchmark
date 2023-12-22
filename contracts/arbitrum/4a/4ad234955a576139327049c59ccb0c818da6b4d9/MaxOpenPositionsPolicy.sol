// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./PolicyBase.sol";
import {IGmxLeveragePositionLib} from "./IGmxLeveragePositionLib.sol";

/// @title MaxOpenPositionsPolicy Contract
/// @notice A policy that restricts the max number of open positions for gmx trade
contract MaxOpenPositionsPolicy is PolicyBase {
    uint256 public constant POSITION_LIMIT = 20;

    mapping(address => uint256) private fundManagerToPositionsCount;

    event TradeSettingsSet(address _fundManager, uint256 maxOpenPositions);

    constructor(address _policyManager) PolicyBase(_policyManager) {}

    /// @notice Adds the initial policy settings for a fund
    /// @param _fundManager The fund's address address
    /// @param _encodedSettings Encoded settings to apply to a fund
    function addTradeSettings(
        address _fundManager,
        bytes calldata _encodedSettings
    ) external override onlyPolicyManager {
        __setTradeSettings(_fundManager, _encodedSettings);
    }

    /// @notice Whether or not the policy can be disabled
    /// @return canDisable_ True if the policy can be disabled
    function canDisable()
        external
        pure
        virtual
        override
        returns (bool canDisable_)
    {
        return true;
    }

    /// @notice Provides a constant string identifier for a policy
    /// @return identifier_ The identifer string
    function identifier()
        external
        pure
        override
        returns (string memory identifier_)
    {
        return "MAX_OPEN_POSITIONS";
    }

    /// @notice Gets the implemented PolicyHooks for a policy
    /// @return implementedHooks_ The implemented PolicyHooks
    function implementedHooks()
        external
        pure
        override
        returns (IPolicyManager.PolicyHook[] memory implementedHooks_)
    {
        implementedHooks_ = new IPolicyManager.PolicyHook[](1);
        implementedHooks_[0] = IPolicyManager.PolicyHook.MaxOpenPositions;
        return implementedHooks_;
    }

    /// @notice Updates the policy settings for a fund
    /// @param _fundManager The fund's address address
    /// @param _encodedSettings Encoded settings to apply to a fund
    function updateTradeSettings(
        address _fundManager,
        bytes calldata _encodedSettings
    ) external override onlyPolicyManager {
        __setTradeSettings(_fundManager, _encodedSettings);
    }

    /// @notice Checks whether a particular condition passes the rule for a particular fund manager
    /// @param _fundManager The fund's address address
    /// @param _externalPosition The investment amount for which to check the rule
    /// @return isValid_ True if the rule passes
    function passesRule(
        address _fundManager,
        address _externalPosition
    ) public view returns (bool isValid_, bytes memory message) {
        uint256 positionsCount = IGmxLeveragePositionLib(_externalPosition)
            .getOpenPositionsCount();

        if (positionsCount <= fundManagerToPositionsCount[_fundManager])
            return (true, "");
        else return (false, bytes("max open position limit breached"));
    }

    /// @notice Apply the rule with the specified parameters of a PolicyHook
    /// @param _fundManager The fund manager address
    /// @param _encodedArgs Encoded args with which to validate the rule
    /// @return isValid True if the rule passes
    /// @return message_ reason string
    /// @dev onlyPolicyManager validation not necessary, as state is not updated and no events are fired
    function validateRule(
        address _fundManager,
        IPolicyManager.PolicyHook,
        bytes calldata _encodedArgs
    ) external view override returns (bool isValid, bytes memory message_) {
        address _externalPosition = __decodeOpenPositionsValidationData(
            _encodedArgs
        );

        return passesRule(_fundManager, _externalPosition);
    }

    /// @dev Helper to set the policy settings for a fund
    /// @param _fundManager The fund's address address
    /// @param _encodedSettings Encoded settings to apply to a fund
    function __setTradeSettings(
        address _fundManager,
        bytes memory _encodedSettings
    ) private {
        uint256 maxPositions = abi.decode(_encodedSettings, (uint256));

        require(
            maxPositions < POSITION_LIMIT,
            "__setTradeSettings: max open positions"
        );

        fundManagerToPositionsCount[_fundManager] = maxPositions;

        emit TradeSettingsSet(_fundManager, maxPositions);
    }

    ///////////////////
    // STATE GETTERS //
    ///////////////////

    /// @notice Gets the max open positions set for a given fund
    /// @param _fundManager The address of the fundManager
    /// @return fundSettings_ The fund settings
    function getTradeSettings(
        address _fundManager
    ) external view override returns (bytes memory) {
        return abi.encode(fundManagerToPositionsCount[_fundManager]);
    }

}
