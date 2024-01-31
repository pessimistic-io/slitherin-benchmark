// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "./IAuthorizerAdaptorEntrypoint.sol";
import "./IGaugeAdder.sol";
import "./IGaugeController.sol";
import "./IL2GaugeCheckpointer.sol";
import "./IStakelessGauge.sol";

import "./Address.sol";
import "./EnumerableSet.sol";
import "./ReentrancyGuard.sol";

import "./GaugeAdder.sol";
import "./ArbitrumRootGauge.sol";

/**
 * @title L2 Gauge Checkpointer
 * @notice Implements IL2GaugeCheckpointer; refer to it for API documentation.
 */
contract L2GaugeCheckpointer is IL2GaugeCheckpointer, ReentrancyGuard, SingletonAuthentication {
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 private immutable _arbitrum = keccak256(abi.encodePacked("Arbitrum"));

    mapping(string => EnumerableSet.AddressSet) private _gauges;
    IAuthorizerAdaptorEntrypoint private immutable _authorizerAdaptorEntrypoint;
    IGaugeAdder private immutable _gaugeAdder;
    IGaugeController private immutable _gaugeController;

    constructor(IGaugeAdder gaugeAdder, IAuthorizerAdaptorEntrypoint authorizerAdaptorEntrypoint)
        SingletonAuthentication(authorizerAdaptorEntrypoint.getVault())
    {
        _gaugeAdder = gaugeAdder;
        _authorizerAdaptorEntrypoint = authorizerAdaptorEntrypoint;
        _gaugeController = gaugeAdder.getGaugeController();
    }

    modifier withValidGaugeType(string memory gaugeType) {
        require(_gaugeAdder.isValidGaugeType(gaugeType), "Invalid gauge type");
        _;
    }

    /// @inheritdoc IL2GaugeCheckpointer
    function getGaugeAdder() external view override returns (IGaugeAdder) {
        return _gaugeAdder;
    }

    /// @inheritdoc IL2GaugeCheckpointer
    function addGaugesWithVerifiedType(string memory gaugeType, IStakelessGauge[] calldata gauges)
        external
        override
        withValidGaugeType(gaugeType)
        authenticate
    {
        // This is a permissioned call, so we can assume that the gauges' type matches the given one.
        // Therefore, we indicate `_addGauges` not to verify the gauge type.
        _addGauges(gaugeType, gauges, true);
    }

    /// @inheritdoc IL2GaugeCheckpointer
    function addGauges(string memory gaugeType, IStakelessGauge[] calldata gauges)
        external
        override
        withValidGaugeType(gaugeType)
    {
        // Since everyone can call this method, the type needs to be verified in the internal `_addGauges` method.
        _addGauges(gaugeType, gauges, false);
    }

    /// @inheritdoc IL2GaugeCheckpointer
    function removeGauges(string memory gaugeType, IStakelessGauge[] calldata gauges)
        external
        override
        withValidGaugeType(gaugeType)
    {
        EnumerableSet.AddressSet storage gaugesForType = _gauges[gaugeType];

        for (uint256 i = 0; i < gauges.length; i++) {
            // Gauges added must come from a valid factory and exist in the controller, and they can't be removed from
            // them. Therefore, the only required check at this point is whether the gauge was killed.
            IStakelessGauge gauge = gauges[i];
            require(gauge.is_killed(), "Gauge was not killed");
            require(gaugesForType.remove(address(gauge)), "Gauge was not added to the checkpointer");

            emit IL2GaugeCheckpointer.GaugeRemoved(gauge, gaugeType, gaugeType);
        }
    }

    /// @inheritdoc IL2GaugeCheckpointer
    function hasGauge(string memory gaugeType, IStakelessGauge gauge)
        external
        view
        override
        withValidGaugeType(gaugeType)
        returns (bool)
    {
        return _gauges[gaugeType].contains(address(gauge));
    }

    /// @inheritdoc IL2GaugeCheckpointer
    function getTotalGauges(string memory gaugeType)
        external
        view
        override
        withValidGaugeType(gaugeType)
        returns (uint256)
    {
        return _gauges[gaugeType].length();
    }

    /// @inheritdoc IL2GaugeCheckpointer
    function getGaugeAtIndex(string memory gaugeType, uint256 index)
        external
        view
        override
        withValidGaugeType(gaugeType)
        returns (IStakelessGauge)
    {
        return IStakelessGauge(_gauges[gaugeType].at(index));
    }

    /// @inheritdoc IL2GaugeCheckpointer
    function checkpointGaugesAboveRelativeWeight(uint256 minRelativeWeight) external payable override nonReentrant {
        // solhint-disable-next-line not-rely-on-time
        uint256 currentPeriod = _roundDownTimestamp(block.timestamp);

        string[] memory gaugeTypes = _gaugeAdder.getGaugeTypes();
        for (uint256 i = 0; i < gaugeTypes.length; ++i) {
            _checkpointGauges(gaugeTypes[i], minRelativeWeight, currentPeriod);
        }

        // Send back any leftover ETH to the caller.
        Address.sendValue(msg.sender, address(this).balance);
    }

    /// @inheritdoc IL2GaugeCheckpointer
    function checkpointGaugesOfTypeAboveRelativeWeight(string memory gaugeType, uint256 minRelativeWeight)
        external
        payable
        override
        nonReentrant
        withValidGaugeType(gaugeType)
    {
        // solhint-disable-next-line not-rely-on-time
        uint256 currentPeriod = _roundDownTimestamp(block.timestamp);

        _checkpointGauges(gaugeType, minRelativeWeight, currentPeriod);

        _returnLeftoverEthIfAny();
    }

    /// @inheritdoc IL2GaugeCheckpointer
    function checkpointSingleGauge(string memory gaugeType, address gauge) external payable override nonReentrant {
        uint256 checkpointCost = getSingleBridgeCost(gaugeType, gauge);

        _authorizerAdaptorEntrypoint.performAction{ value: checkpointCost }(
            gauge,
            abi.encodeWithSelector(IStakelessGauge.checkpoint.selector)
        );

        _returnLeftoverEthIfAny();
    }

    /// @inheritdoc IL2GaugeCheckpointer
    function getSingleBridgeCost(string memory gaugeType, address gauge) public view override returns (uint256) {
        require(_gauges[gaugeType].contains(gauge), "Gauge was not added to the checkpointer");

        if (keccak256(abi.encodePacked(gaugeType)) == _arbitrum) {
            return ArbitrumRootGauge(gauge).getTotalBridgeCost();
        } else {
            return 0;
        }
    }

    /// @inheritdoc IL2GaugeCheckpointer
    function getTotalBridgeCost(uint256 minRelativeWeight) external view override returns (uint256) {
        // solhint-disable-next-line not-rely-on-time
        uint256 currentPeriod = _roundDownTimestamp(block.timestamp);
        uint256 totalArbitrumGauges = _gauges["Arbitrum"].length();
        EnumerableSet.AddressSet storage arbitrumGauges = _gauges["Arbitrum"];
        uint256 totalCost;

        for (uint256 i = 0; i < totalArbitrumGauges; ++i) {
            address gauge = arbitrumGauges.unchecked_at(i);
            // Skip gauges that are below the threshold.
            if (_gaugeController.gauge_relative_weight(gauge, currentPeriod) < minRelativeWeight) {
                continue;
            }

            // Cost per gauge might not be the same if gauges come from different factories, so we add each
            // gauge's bridge cost individually.
            totalCost += ArbitrumRootGauge(gauge).getTotalBridgeCost();
        }
        return totalCost;
    }

    /// @inheritdoc IL2GaugeCheckpointer
    function isValidGaugeType(string memory gaugeType) external view override returns (bool) {
        return _gaugeAdder.isValidGaugeType(gaugeType);
    }

    function _addGauges(
        string memory gaugeType,
        IStakelessGauge[] calldata gauges,
        bool isGaugeTypeVerified
    ) internal {
        EnumerableSet.AddressSet storage gaugesForType = _gauges[gaugeType];

        for (uint256 i = 0; i < gauges.length; i++) {
            IStakelessGauge gauge = gauges[i];
            // Gauges must come from a valid factory to be added to the gauge controller, so gauges that don't pass
            // the valid factory check will be rejected by the controller.
            require(_gaugeController.gauge_exists(address(gauge)), "Gauge was not added to the GaugeController");
            require(!gauge.is_killed(), "Gauge was killed");
            require(gaugesForType.add(address(gauge)), "Gauge already added to the checkpointer");

            // To ensure that the gauge effectively corresponds to the given type, we query the gauge factory registered
            // in the gauge adder for the gauge type.
            // However, since gauges may come from older factories from previous adders, we need to be able to override
            // this check. This way we can effectively still add older gauges to the checkpointer via authorized calls.
            require(
                isGaugeTypeVerified || _gaugeAdder.getFactoryForGaugeType(gaugeType).isGaugeFromFactory(address(gauge)),
                "Gauge does not correspond to the selected type"
            );

            emit IL2GaugeCheckpointer.GaugeAdded(gauge, gaugeType, gaugeType);
        }
    }

    /**
     * @dev Performs checkpoints for all gauges of the given type whose relative weight is at least the specified one.
     * @param gaugeType Type of the gauges to checkpoint.
     * @param minRelativeWeight Threshold to filter out gauges below it.
     * @param currentPeriod Current block time rounded down to the start of the week.
     * This method doesn't check whether the caller transferred enough ETH to cover the whole operation.
     */
    function _checkpointGauges(
        string memory gaugeType,
        uint256 minRelativeWeight,
        uint256 currentPeriod
    ) private {
        EnumerableSet.AddressSet storage typeGauges = _gauges[gaugeType];

        uint256 totalTypeGauges = typeGauges.length();
        if (totalTypeGauges == 0) {
            // Return early if there's no work to be done.
            return;
        }

        // Arbitrum gauges need to send ETH when performing the checkpoint to pay for bridge costs. Furthermore,
        // if gauges come from different factories, the cost per gauge might not be the same for all gauges.
        function(address) internal performCheckpoint = (keccak256(abi.encodePacked(gaugeType)) == _arbitrum)
            ? _checkpointArbitrumGauge
            : _checkpointCostlessBridgeGauge;

        for (uint256 i = 0; i < totalTypeGauges; ++i) {
            address gauge = typeGauges.unchecked_at(i);
            // Skip gauges that are below the threshold.
            if (_gaugeController.gauge_relative_weight(gauge, currentPeriod) < minRelativeWeight) {
                continue;
            }
            performCheckpoint(gauge);
        }
    }

    /**
     * @dev Performs checkpoint for Arbitrum gauge, forwarding ETH to pay bridge costs.
     */
    function _checkpointArbitrumGauge(address gauge) private {
        uint256 checkpointCost = ArbitrumRootGauge(gauge).getTotalBridgeCost();
        _authorizerAdaptorEntrypoint.performAction{ value: checkpointCost }(
            gauge,
            abi.encodeWithSelector(IStakelessGauge.checkpoint.selector)
        );
    }

    /**
     * @dev Performs checkpoint for non-Arbitrum gauge; does not forward any ETH.
     */
    function _checkpointCostlessBridgeGauge(address gauge) private {
        _authorizerAdaptorEntrypoint.performAction(gauge, abi.encodeWithSelector(IStakelessGauge.checkpoint.selector));
    }

    function _returnLeftoverEthIfAny() private {
        // Send back any leftover ETH to the caller.
        // Most gauge types don't need to send value, and this step can be skipped in those cases.
        uint256 remainingBalance = address(this).balance;
        if (remainingBalance > 0) {
            Address.sendValue(msg.sender, remainingBalance);
        }
    }

    /**
     * @dev Rounds the provided timestamp down to the beginning of the current week (Thurs 00:00 UTC).
     */
    function _roundDownTimestamp(uint256 timestamp) private pure returns (uint256) {
        // Division by zero or overflows are impossible here.
        return (timestamp / 1 weeks) * 1 weeks;
    }
}

