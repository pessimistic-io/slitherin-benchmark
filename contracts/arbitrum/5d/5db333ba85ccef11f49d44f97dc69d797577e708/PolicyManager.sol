// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IPolicy} from "./IPolicy.sol";
import {IPolicyManager} from "./IPolicyManager.sol";
import {AddressArrayLib} from "./AddressArrayLib.sol";
import {IAlgoTradeManager} from "./IAlgoTradeManager.sol";

/// @title PolicyManager Contract
/// @notice Manages policies for fund
/// Policies that restrict current strategy creator can only be added upon fund setup, or reconfiguration.
/// Policies themselves specify whether or not they are allowed to be updated or removed.
contract PolicyManager is IPolicyManager {
    using AddressArrayLib for address[];

    event PolicyDisabledOnHookForWrapper(
        address indexed fundManager,
        address indexed policy,
        PolicyHook indexed hook
    );

    event PolicyEnabledForWrapper(
        address indexed fundManager,
        address indexed policy,
        bytes settingsData
    );

    uint256 private constant POLICY_HOOK_COUNT = 8;

    address public fundManagerFactory;

    mapping(address => mapping(PolicyHook => address[]))
        private fundManagerToHookToPolicies;

    modifier onlyFundOwner(address _fundManager) {
        require(
            msg.sender == IAlgoTradeManager(_fundManager).strategyCreator(),
            "Only the fund manager contract can call this function"
        );
        _;
    }

    modifier onlyFactory() {
        require(
            msg.sender == fundManagerFactory,
            "Only the factory contract can call this function"
        );
        _;
    }

    constructor(address _factory) {
        fundManagerFactory = _factory;
    }

    // EXTERNAL FUNCTIONS

    /// @notice Disables a policy for a fund
    /// @param _fundManager The fundManager of the fund
    /// @param _policy The policy address to disable
    /// @dev If an arbitrary policy changes its `implementedHooks()` return values after it is
    /// already enabled on a fund, then this will not correctly disable the policy from any
    /// removed hook values.
    function disablePolicyForFund(
        address _fundManager,
        address _policy
    ) external onlyFundOwner(_fundManager) {
        require(
            IPolicy(_policy).canDisable(),
            "disablePolicyForFund: _policy cannot be disabled"
        );

        PolicyHook[] memory implementedHooks = IPolicy(_policy)
            .implementedHooks();
        for (uint256 i; i < implementedHooks.length; i++) {
            bool disabled = fundManagerToHookToPolicies[_fundManager][
                implementedHooks[i]
            ].removeStorageItem(_policy);
            if (disabled) {
                emit PolicyDisabledOnHookForWrapper(
                    _fundManager,
                    _policy,
                    implementedHooks[i]
                );
            }
        }
    }

    /// @notice Enables a policy for a fund
    /// @param _fundManager The fundManager of the fund
    /// @param _policy The policy address to enable
    /// @param _settingsData The encoded settings data with which to configure the policy
    /// @dev Disabling a policy does not delete fund config on the policy, so if a policy is
    /// disabled and then enabled again, its initial state will be the previous config. It is the
    /// policy's job to determine how to merge that config with the _settingsData param in this function.
    function enablePolicyForFund(
        address _fundManager,
        bytes calldata _settingsData,
        address _policy
    ) external onlyFundOwner(_fundManager) {
        PolicyHook[] memory implementedHooks = IPolicy(_policy)
            .implementedHooks();

        __enablePolicyForFund(
            _fundManager,
            _policy,
            _settingsData,
            implementedHooks
        );

        // __activatePolicyForFund(_fundManager, _policy);
    }

    /// @notice Enable policies for use in a fund
    /// @param _fundManager The fundManager of the fund
    /// @param _configData Encoded config data
    function setConfigForFund(
        address _fundManager,
        bytes calldata _configData
    ) external onlyFactory {
        // In case there are no policies yet
        if (_configData.length == 0) {
            return;
        }

        (address[] memory policies, bytes[] memory settingsData) = abi.decode(
            _configData,
            (address[], bytes[])
        );

        // Sanity check
        require(
            policies.length == settingsData.length,
            "setConfigForFund: policies and settingsData array lengths unequal"
        );

        // Enable each policy with settings
        for (uint256 i; i < policies.length; i++) {
            __enablePolicyForFund(
                _fundManager,
                policies[i],
                settingsData[i],
                IPolicy(policies[i]).implementedHooks()
            );
        }
    }

    /// @notice Updates policies settings for a fund
    /// @param _fundManager The fundManager of the fund
    /// @param _policies The Policy contracts to update
    /// @param _settingsData The encoded settings data with which to update the policy config
    function updatePolicySettingsForFund(
        address _fundManager,
        address[] memory _policies,
        bytes[] memory _settingsData
    ) external onlyFundOwner(_fundManager) {
        uint256 iterations = _policies.length;
        require(iterations == _settingsData.length, "unequal arrays");
        for(uint256 i; i< iterations; ++i){
        IPolicy(_policies[i]).updateTradeSettings(_fundManager, _settingsData[i]);
        }
    }   

    /// @notice Validates all policies that apply to a given hook for a fund
    /// @param _fundManager The fundManager of the fund
    /// @param _hook The PolicyHook for which to validate policies
    /// @param _validationData The encoded data with which to validate the filtered policies
    function validatePolicies(
        address _fundManager,
        PolicyHook _hook,
        bytes calldata _validationData
    ) external override returns (bool canExec, bytes memory message) {
        // Return as quickly as possible if no policies to run
        address[] memory policies = getEnabledPoliciesOnHookForFund(
            _fundManager,
            _hook
        );
        if (policies.length == 0) {
            return (true, bytes("no policies"));
        }

        // Limit calls to trusted components, in case policies update local storage upon runs
        // require(
        //     msg.sender == _fundManager || msg.sender == fundManagerFactory,
        //     "validatePolicies: Caller not allowed"
        // );

        (canExec, message) = IPolicy(policies[0]).validateRule(
            _fundManager,
            _hook,
            _validationData
        );
    }

    // PRIVATE FUNCTIONS

    // /// @dev Helper to activate a policy for a fund
    // function __activatePolicyForFund(address _fundManager, address _policy) private {
    //     IPolicy(_policy).activateForTradeManager(_fundManager);
    // }

    /// @dev Helper to set config and enable policies for a fund
    function __enablePolicyForFund(
        address _fundManager,
        address _policy,
        bytes memory _settingsData,
        PolicyHook[] memory _hooks
    ) private {
        // Set fund config on policy
        if (_settingsData.length > 0) {
            IPolicy(_policy).addTradeSettings(_fundManager, _settingsData);
        }

        // Add policy
        for (uint256 i; i < _hooks.length; i++) {
            require(
                !policyIsEnabledOnHookForFund(_fundManager, _hooks[i], _policy),
                "__enablePolicyForFund: Policy is already enabled"
            );
            fundManagerToHookToPolicies[_fundManager][_hooks[i]].push(_policy);
        }

        emit PolicyEnabledForWrapper(_fundManager, _policy, _settingsData);
    }

    /// @dev Helper to get all the hooks available to policies
    function getAllPolicyHooks()
        public
        pure
        returns (PolicyHook[POLICY_HOOK_COUNT] memory hooks_)
    {
        return [
            PolicyHook.MinMaxLeverage,
            PolicyHook.MaxOpenPositions,
            PolicyHook.PreExecuteTrade,
            PolicyHook.TradeFactor,
            PolicyHook.MaxAmountPerTrade,
            PolicyHook.MinAssetBalances,
            PolicyHook.TrailingStopLoss,
            PolicyHook.PostExecuteTrade
        ];
    }

    ///////////////////
    // STATE GETTERS //
    ///////////////////

    /// @notice Get a list of enabled policies for the given fund
    /// @param _fundManager The fundManager
    /// @return enabledPolicies_ The array of enabled policy addresses
    function getEnabledPoliciesForFund(
        address _fundManager
    ) public view returns (address[] memory enabledPolicies_) {
        PolicyHook[POLICY_HOOK_COUNT] memory hooks = getAllPolicyHooks();

        for (uint256 i; i < hooks.length; i++) {
            enabledPolicies_ = enabledPolicies_.mergeArray(
                getEnabledPoliciesOnHookForFund(_fundManager, hooks[i])
            );
        }

        return enabledPolicies_;
    }

    /// @notice Get a list of enabled policies that run on a given hook for the given fund
    /// @param _fundManager The fundManager
    /// @param _hook The PolicyHook
    /// @return enabledPolicies_ The array of enabled policy addresses
    function getEnabledPoliciesOnHookForFund(
        address _fundManager,
        PolicyHook _hook
    ) public view returns (address[] memory enabledPolicies_) {
        return fundManagerToHookToPolicies[_fundManager][_hook];
    }

    /// @notice Check whether a given policy runs on a given hook for a given fund
    /// @param _fundManager The fundManager
    /// @param _hook The PolicyHook
    /// @param _policy The policy
    /// @return isEnabled_ True if the policy is enabled
    function policyIsEnabledOnHookForFund(
        address _fundManager,
        PolicyHook _hook,
        address _policy
    ) public view returns (bool isEnabled_) {
        return
            getEnabledPoliciesOnHookForFund(_fundManager, _hook).contains(
                _policy
            );
    }

    function getTraderConfigData(
        address _fundManager
    )
        public
        view
        returns (
            uint256 minLeverage,
            uint256 maxLeverage,
            uint256 maxOpenPositions,
            uint256 tradeFactor,
            uint256 maxAmountPerTrade,
            uint256 minAssetBalances
        )
    {
        address[] memory policies = this.getEnabledPoliciesForFund(
            _fundManager
        );

        for (uint256 i; i < policies.length; i++) {
            address policy = policies[i];

            PolicyHook hook = IPolicy(policy).implementedHooks()[0];

            if (hook == PolicyHook.MaxOpenPositions)
                maxOpenPositions = abi.decode(
                    IPolicy(policy).getTradeSettings(_fundManager),
                    (uint256)
                );
            else if (hook == PolicyHook.MinMaxLeverage)
                (minLeverage, maxLeverage) = abi.decode(
                    IPolicy(policy).getTradeSettings(_fundManager),
                    (uint256, uint256)
                );
            else if (hook == PolicyHook.TradeFactor)
                tradeFactor = abi.decode(
                    IPolicy(policy).getTradeSettings(_fundManager),
                    (uint256)
                );
            else if (hook == PolicyHook.MaxAmountPerTrade)
                maxAmountPerTrade = abi.decode(
                    IPolicy(policy).getTradeSettings(_fundManager),
                    (uint256)
                );
            else if (hook == PolicyHook.MinAssetBalances)
                minAssetBalances = abi.decode(
                    IPolicy(policy).getTradeSettings(_fundManager),
                    (uint256)
                );
        }
    }
}

