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

import "./IPoolVersion.sol";
import "./IVersion.sol";
import "./IVault.sol";

import "./BasePoolFactory.sol";
import "./FactoryWidePauseWindow.sol";

import "./ComposableStablePool.sol";

contract ComposableStablePoolFactory is IVersion, IPoolVersion, BasePoolFactory, FactoryWidePauseWindow {
    string private _version;
    string private _poolVersion;

    constructor(
        IVault vault,
        IProtocolFeePercentagesProvider protocolFeeProvider,
        string memory factoryVersion,
        string memory poolVersion
    ) BasePoolFactory(vault, protocolFeeProvider, type(ComposableStablePool).creationCode) {
        _version = factoryVersion;
        _poolVersion = poolVersion;
    }

    function version() external view override returns (string memory) {
        return _version;
    }

    function getPoolVersion() public view override returns (string memory) {
        return _poolVersion;
    }

    /**
     * @dev Deploys a new `ComposableStablePool`.
     */
    function create(
        string memory name,
        string memory symbol,
        IERC20[] memory tokens,
        uint256 amplificationParameter,
        IRateProvider[] memory rateProviders,
        uint256[] memory tokenRateCacheDurations,
        bool exemptFromYieldProtocolFeeFlag,
        uint256 swapFeePercentage,
        address owner,
        bytes32 salt
    ) external returns (ComposableStablePool) {
        (uint256 pauseWindowDuration, uint256 bufferPeriodDuration) = getPauseConfiguration();
        return
            ComposableStablePool(
                _create(
                    abi.encode(
                        ComposableStablePool.NewPoolParams({
                            vault: getVault(),
                            protocolFeeProvider: getProtocolFeePercentagesProvider(),
                            name: name,
                            symbol: symbol,
                            tokens: tokens,
                            rateProviders: rateProviders,
                            tokenRateCacheDurations: tokenRateCacheDurations,
                            exemptFromYieldProtocolFeeFlag: exemptFromYieldProtocolFeeFlag,
                            amplificationParameter: amplificationParameter,
                            swapFeePercentage: swapFeePercentage,
                            pauseWindowDuration: pauseWindowDuration,
                            bufferPeriodDuration: bufferPeriodDuration,
                            owner: owner,
                            version: getPoolVersion()
                        })
                    ),
                    salt
                )
            );
    }
}

