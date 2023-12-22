// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./Ownable.sol";
import "./Pausable.sol";
import "./IOracleConnector.sol";

abstract contract OracleConnector is IOracleConnector, Ownable, Pausable {
    string public name;
    uint256 public immutable decimals;

    function validateTimestamp(uint256 timestamp) external view virtual returns (bool);

    function paused() public view override returns (bool) {
        return super.paused();
    }

    function getPrice() external view virtual returns (uint256);

    constructor(string memory name_, uint256 decimals_) Ownable() Pausable() {
        name = name_;
        decimals = decimals_;
    }

    function togglePause() external onlyOwner returns (bool) {
        if (paused()) _unpause();
        else _pause();
        return true;
    }
}

