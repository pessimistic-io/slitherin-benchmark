// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./IOracle.sol";
import "./IGmxGlpManager.sol";

contract GlpOracle is IOracle {
    IGmxGlpManager private immutable glpManager;

    constructor(IGmxGlpManager glpManager_) {
        glpManager = glpManager_;
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function _get() internal view returns (uint256) {
        return 1e48 / glpManager.getPrice(false);
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
        return "Glp USD Oracle";
    }

    /// @inheritdoc IOracle
    function symbol(bytes calldata) public pure override returns (string memory) {
        return "Glp/USD";
    }
}

