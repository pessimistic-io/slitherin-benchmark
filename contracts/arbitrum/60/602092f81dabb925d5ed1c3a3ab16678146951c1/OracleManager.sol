// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "./Ownable.sol";

import "./IOracleManager.sol";
import "./Oracle.sol";

contract OracleManager is Ownable, IOracleManager {
    /// @dev counter => oracle address
    mapping(uint256 => address) public oracles;
    /// @dev Registered oracle count;
    uint256 public count;

    event OracleAdded(address indexed oracle);

    function registerOracle(address oracle) external onlyOwner {
        require(oracle != address(0), "ZERO_ADDRESS");
        oracles[count] = oracle;
        count++;

        emit OracleAdded(address(oracle));
    }
}

