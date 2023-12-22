/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./Strings.sol";

/// @title Test middleware contract for automated relaying of data.
/// @author Tales of Elleria | Ellerian Prince - Wayne
contract SimpleMiddleware is Ownable {
    using Strings for uint256;

    /// @notice Holds our relayed data.
    mapping (string => uint256) data;

    /// @notice Returns the paired value for the given key.
    /// @param key Key to obtain data for.
    /// @return Value of the given key.
    function GetData(string memory key) external view returns (uint256) {
        return data[key];
    }

    /// @notice Returns paired values for all given key, in order.
    /// @param keys Keys to obtain data for.
    /// @return Value of the given kes, delimited by comma.
    function GetData(string[] memory keys) external view returns (string memory) {
        require(keys.length > 1, "SimpleMiddleware: invalid keys length");

        bytes memory b = abi.encodePacked(Strings.toString(data[keys[0]]));
        string memory value = string(b);

        for (uint256 i = 1; i < keys.length; i += 1) {
            b = abi.encodePacked(value, ",", Strings.toString(data[keys[i]]));
            value = string(b);
        }

        return string(b);
    }

    /// @notice Updates the value of the given key.
    /// @param key key
    /// @param value value
    function WriteData(string memory key, uint256 value) external onlyOwner {
        data[key] = value;
    }

    /// @notice Updates the values of the given keys.
    /// @param keys keys to update
    /// @param values values to update
    /// @dev Sequence of keys and values must be matching.
    function WriteData(string[] memory keys, uint256[] memory values) external onlyOwner {
        require(keys.length == values.length, "SimpleMiddleware: invalid lengths");
        for (uint256 i = 0; i < keys.length; i += 1) {
            data[keys[i]] = values[i];
        }
    }
}
