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

import "./IVault.sol";

import "./BasePoolFactory.sol";
import "./FactoryWidePauseWindow.sol";

import "./WeightedPool.sol";

contract WeightedPoolFactory is BasePoolFactory, FactoryWidePauseWindow {
    string private _factoryVersion;
    string private _poolVersion;

    constructor(
        IVault vault,
        IProtocolFeePercentagesProvider protocolFeeProvider,
        string memory factoryVersion,
        string memory poolVersion
    ) BasePoolFactory(vault, protocolFeeProvider, type(WeightedPool).creationCode) {
        _factoryVersion = factoryVersion;
        _poolVersion = poolVersion;
    }

    /**
     * @notice Returns a JSON representation of the contract version containing name, version number and task ID.
     */
    function version() external view returns (string memory) {
        return _factoryVersion;
    }

    /**
     * @notice Returns a JSON representation of the deployed pool version containing name, version number and task ID.
     *
     * @dev This is typically only useful in complex Pool deployment schemes, where multiple subsystems need to know
     * about each other. Note that this value will only be updated at factory creation time.
     */
    function getPoolVersion() public view returns (string memory) {
        return _poolVersion;
    }

    /**
     * @dev Deploys a new `WeightedPool`.
     */
    function create(
        string memory name,
        string memory symbol,
        IERC20[] memory tokens,
        uint256[] memory normalizedWeights,
        IRateProvider[] memory rateProviders,
        uint256 swapFeePercentage,
        address owner
    ) external returns (address) {
        (uint256 pauseWindowDuration, uint256 bufferPeriodDuration) = getPauseConfiguration();

        return
            _create(
                abi.encode(
                    WeightedPool.NewPoolParams({
                        name: name,
                        symbol: symbol,
                        tokens: tokens,
                        normalizedWeights: normalizedWeights,
                        rateProviders: rateProviders,
                        assetManagers: new address[](tokens.length), // Don't allow asset managers,
                        swapFeePercentage: swapFeePercentage
                    }),
                    getVault(),
                    getProtocolFeePercentagesProvider(),
                    pauseWindowDuration,
                    bufferPeriodDuration,
                    owner,
                    getPoolVersion()
                )
            );
    }
}

