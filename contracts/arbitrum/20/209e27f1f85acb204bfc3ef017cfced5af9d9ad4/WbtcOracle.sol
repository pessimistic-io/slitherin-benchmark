// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./IOracle.sol";
import "./IAggregator.sol";

contract WbtcOracle is IOracle {
    IAggregator private immutable aggregator;

    constructor(address _aggregator) {
        aggregator = IAggregator(_aggregator);
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function _get() internal view returns (uint256) {
        return 1e16 / uint256(aggregator.latestAnswer());
    }

    // Get the latest exchange rate
    /// @inheritdoc IOracle
    function get(bytes calldata) public view override returns (bool, uint256) {
        return (true, _get());
    }

    // Check the last exchange rate without any state changes
    /// @inheritdoc IOracle
    function peek(bytes calldata) public view override returns (bool, uint256) {
        return (true, _get());
    }

    // Check the current spot exchange rate without any state changes
    /// @inheritdoc IOracle
    function peekSpot(bytes calldata data) external view override returns (uint256 rate) {
        (, rate) = peek(data);
    }

    /// @inheritdoc IOracle
    function name(bytes calldata) public pure override returns (string memory) {
        return "WBTC USD Oracle";
    }

    /// @inheritdoc IOracle
    function symbol(bytes calldata) public pure override returns (string memory) {
        return "WBTC/USD";
    }
}

