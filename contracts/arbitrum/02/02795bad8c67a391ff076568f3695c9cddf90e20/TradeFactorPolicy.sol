// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./PolicyBase.sol";
import {IGmxHelper} from "./IGmxHelper.sol";
import {IAlgoTradeManager} from "./IAlgoTradeManager.sol";
import {IFundManagerFactory} from "./IFundManagerFactory.sol";

/// @title TradeFactorPolicy Contract
/// @notice A policy that restricts the collateral and size of the position to be copied
contract TradeFactorPolicy is PolicyBase {
    uint256 public constant BASIS_POINTS_DIVISOR = 10000;

    IGmxHelper private gmxHelper;

    mapping(address => uint256) private fundManagerToTradeFactor;

    event TradeSettingsSet(address fundManager, uint256 tradeFactor);

    constructor(
        address _policyManager,
        address _gmxHelper
    )
        // address _gmxHelper
        PolicyBase(_policyManager)
    {
        gmxHelper = IGmxHelper(_gmxHelper);
    }

    function setGmxHelper(address _gmxHelper) external {
        require(
            msg.sender ==
                IFundManagerFactory(
                    IPolicyManager(POLICY_MANAGER).fundManagerFactory()
                ).owner(),
            "setGmxHelper: invalid caller"
        );
        gmxHelper = IGmxHelper(_gmxHelper);
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

    function addTradeSettings(
        address _fundManager,
        bytes calldata _encodedSettings
    ) external {
        __setTradeSettings(_fundManager, _encodedSettings);
    }

    /** @notice Updates the policy settings for a fund
        @param _fundManager The fund's address address
        @param _encodedSettings Encoded settings to apply to a fund
    */
    function updateTradeSettings(
        address _fundManager,
        bytes calldata _encodedSettings
    ) external override onlyPolicyManager {
        __setTradeSettings(_fundManager, _encodedSettings);
    }

    /// @dev Helper to set the policy settings for a fund
    /// @param _fundManager The fund's address address
    /// @param _encodedSettings Encoded settings to apply to a fund
    function __setTradeSettings(
        address _fundManager,
        bytes memory _encodedSettings
    ) private {
        uint256 tradeFactor = abi.decode(_encodedSettings, (uint256));

        fundManagerToTradeFactor[_fundManager] = tradeFactor;

        emit TradeSettingsSet(_fundManager, tradeFactor);
    }

    /// @notice Provides a constant string identifier for a policy
    /// @return identifier_ The identifer string
    function identifier()
        external
        pure
        override
        returns (string memory identifier_)
    {
        return "TRADE_FACTOR";
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
        implementedHooks_[0] = IPolicyManager.PolicyHook.TradeFactor;

        return implementedHooks_;
    }

    /// @notice Apply the rule with the specified parameters of a PolicyHook
    /// @param _fundManager The fund manager address
    /// @param _encodedArgs Encoded args with which to validate the rule
    /// @return isValid_ True if the rule passes
    /// @dev onlyPolicyManager validation not necessary, as state is not updated and no events are fired
    function validateRule(
        address _fundManager,
        IPolicyManager.PolicyHook,
        bytes calldata _encodedArgs
    ) external view override returns (bool isValid_, bytes memory message) {
        return passesRule(_fundManager, _encodedArgs);
    }

    // / @notice Checks whether a particular condition passes the rule for a particular fund
    // / @param actionId action id
    // / @param _fundManager The fund's address address
    // / @param data validation data
    // / @return isValid_ True if the rule passes
    function passesRule(
        address _fundManager,
        bytes memory data
    ) public view returns (bool isValid_, bytes memory) {
        (uint256 sizeDelta, uint256 collateralDelta) = abi.decode(
            data,
            (uint256, uint256)
        );

        uint256 positionFactor = fundManagerToTradeFactor[_fundManager];

        if (positionFactor != 0) {
            sizeDelta = (sizeDelta * positionFactor) / BASIS_POINTS_DIVISOR;
            collateralDelta =
                (collateralDelta * positionFactor) /
                BASIS_POINTS_DIVISOR;
            return (true, abi.encode(sizeDelta, collateralDelta));
        } else return (false, "");
    }

    function getTradeSettings(
        address _fundManager
    ) external view override returns (bytes memory) {
        return abi.encode(fundManagerToTradeFactor[_fundManager]);
    }
}

