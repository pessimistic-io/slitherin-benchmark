// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "./UniswapV3DeltaNeutralStrategy.sol";

/**
 * @notice Strategy that borrows from LendVault and deposits into a uni v3 pool
 */
contract UniswapV3DirectionalStrategy is UniswapV3DeltaNeutralStrategy {

    /**
     * @notice Initialize upgradeable contract
     */
    function initialize(
        address _provider,
        Addresses memory _addresses,
        Thresholds memory _thresholds,
        Parameters memory _parameters
    ) external override initializer {
        _UniswapV3BaseStrategy__init(_provider, _addresses, _thresholds, _parameters);
    }

    /// @inheritdoc UniswapV3BaseStrategy
    function getAddresses() public virtual override view returns (address want, address stableToken, address volatileToken, address positionsManager) {
        want = addresses.want;
        stableToken = addresses.volatileToken;
        volatileToken = addresses.stableToken;
        positionsManager = addresses.positionsManager;
    }

    /// @inheritdoc UniswapV3BaseStrategy
    function strategyType() external virtual pure override returns (string memory) {
        return "Directional";
    }
}
