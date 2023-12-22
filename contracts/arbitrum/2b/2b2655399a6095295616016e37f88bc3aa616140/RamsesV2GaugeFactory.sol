// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;

import "./IRamsesV2GaugeFactory.sol";

import "./RamsesV2GaugeDeployer.sol";

import "./IGaugeV2.sol";

import "./Initializable.sol";

/// @title Canonical Ramses V2 factory
/// @notice Deploys Ramses V2 pools and manages ownership and control over pool protocol fees
contract RamsesV2GaugeFactory is
    IRamsesV2GaugeFactory,
    RamsesV2GaugeDeployer,
    Initializable
{
    /// @inheritdoc IRamsesV2GaugeFactory
    address public override owner;
    /// @inheritdoc IRamsesV2GaugeFactory
    address public override nfpManager;
    /// @inheritdoc IRamsesV2GaugeFactory
    address public override veRam;
    /// @inheritdoc IRamsesV2GaugeFactory
    address public override voter;

    /// @inheritdoc IRamsesV2GaugeFactory
    mapping(address => address) public override getGauge;

    /// @inheritdoc IRamsesV2GaugeFactory
    address public override feeCollector;

    // pool specific fee protocol if set
    mapping(address => uint8) _poolFeeProtocol;

    /// @dev prevents implementation from being initialized later
    constructor() initializer() {}

    function initialize(
        address _nfpManager,
        address _veRam,
        address _voter,
        address _feeCollector,
        address _implementation
    ) public initializer {
        owner = msg.sender;
        nfpManager = _nfpManager;
        veRam = _veRam;
        voter = _voter;
        feeCollector = _feeCollector;
        implementation = _implementation;

        emit OwnerChanged(address(0), msg.sender);
    }

    /// @inheritdoc IRamsesV2GaugeFactory
    function createGauge(
        address pool
    ) external override returns (address gauge) {
        require(getGauge[pool] == address(0), "GE");
        gauge = _deploy(voter, nfpManager, feeCollector, pool);
        getGauge[pool] = gauge;
        emit GaugeCreated(pool, gauge);
    }

    /// @inheritdoc IRamsesV2GaugeFactory
    function setOwner(address _owner) external override {
        require(msg.sender == owner, "AUTH");
        emit OwnerChanged(owner, _owner);
        owner = _owner;
    }

    /// @dev Sets implementation for beacon proxies
    /// @param _implementation new implementation address
    function setImplementation(address _implementation) external {
        require(msg.sender == owner, "AUTH");
        emit ImplementationChanged(implementation, _implementation);
        implementation = _implementation;
    }
}

