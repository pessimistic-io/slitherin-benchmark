// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;

import "./IRamsesV2GaugeDeployer.sol";
import "./IGaugeV2.sol";

import "./RamsesBeaconProxy.sol";

import "./IBeacon.sol";

contract RamsesV2GaugeDeployer is IRamsesV2GaugeDeployer, IBeacon {
    /// @inheritdoc IBeacon
    address public override implementation;

    /// @dev Deploys a pool with the given parameters by transiently setting the parameters storage slot and then
    /// clearing it after deploying the pool.
    /// @param _voter The address of the voter to set.
    /// @param _feeCollector The address of the fee collector to set.
    /// @param _pool The address of the pool to set.
    function _deploy(
        address _voter,
        address _nfpManager,
        address _feeCollector,
        address _pool
    ) internal returns (address gauge) {
        gauge = address(
            new RamsesBeaconProxy{
                salt: keccak256(abi.encodePacked(msg.sender, _pool))
            }()
        );
        IGaugeV2(gauge).initialize(
            address(this),
            _voter,
            _nfpManager,
            _feeCollector,
            _pool
        );
    }
}

