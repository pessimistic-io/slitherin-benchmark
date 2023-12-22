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

import "./BasePoolFactory.sol";
import "./IProtocolFeePercentagesProvider.sol";
import "./FactoryWidePauseWindow.sol";

import "./ManagedPool.sol";
import "./ExternalWeightedMath.sol";

/**
 * @dev This is a base factory designed to be called from other factories to deploy a ManagedPool
 * with a particular contract as the owner. This contract might have a privileged or admin account
 * to perform permissioned actions: this account is often called the pool manager.
 *
 * This factory should NOT be used directly to deploy ManagedPools owned by EOAs. ManagedPools
 * owned by EOAs would be very dangerous for LPs. There are no restrictions on what the owner
 * can do, so a malicious owner could easily manipulate prices and drain the pool.
 *
 * In this design, other client-specific factories will deploy a contract, then call this factory
 * to deploy the pool, passing in that contract address as the owner.
 */
contract ManagedPoolFactory is BasePoolFactory, FactoryWidePauseWindow {
    IExternalWeightedMath private immutable _weightedMath;

    constructor(IVault vault, IProtocolFeePercentagesProvider protocolFeeProvider)
        BasePoolFactory(vault, protocolFeeProvider, type(ManagedPool).creationCode)
    {
        _weightedMath = new ExternalWeightedMath();
    }

    function getWeightedMath() external view returns (IExternalWeightedMath) {
        return _weightedMath;
    }

    /**
     * @dev Deploys a new `ManagedPool`. The owner should be a contract, deployed by another factory.
     */
    function create(ManagedPoolSettings.NewPoolParams memory poolParams, address owner)
        external
        returns (address pool)
    {
        (uint256 pauseWindowDuration, uint256 bufferPeriodDuration) = getPauseConfiguration();

        return
            _create(
                abi.encode(
                    poolParams,
                    getVault(),
                    getProtocolFeePercentagesProvider(),
                    _weightedMath,
                    owner,
                    pauseWindowDuration,
                    bufferPeriodDuration
                )
            );
    }
}

