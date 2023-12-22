// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./EnumerableSet.sol";
import "./ERC20.sol";

import "./DefaultAccessControl.sol";

import "./IMellowBaseOracle.sol";

contract OracleRegistry is DefaultAccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;
    error OracleNotFound();

    struct OracleData {
        IBaseOracle oracle;
        IBaseOracle.SecurityParams params;
    }

    mapping(address => OracleData) public erc20Oracles;
    mapping(uint256 => OracleData) public mellowOracles;
    uint256 public numberOfMellowOracles;

    EnumerableSet.AddressSet private _supportedTokens;

    constructor(address admin) DefaultAccessControl(admin) {}

    function updateBaseOracles(address[] calldata tokens, OracleData[] calldata newOracles) external {
        _requireAdmin();
        for (uint256 i = 0; i < tokens.length; i++) {
            if (address(newOracles[i].oracle) == address(0)) {
                _supportedTokens.remove(tokens[i]);
            } else {
                _supportedTokens.add(tokens[i]);
            }
            erc20Oracles[tokens[i]] = newOracles[i];
        }
    }

    function supportedTokens() public view returns (address[] memory) {
        return _supportedTokens.values();
    }

    function updateMellowOracles(OracleData[] memory oracles) external {
        _requireAdmin();
        for (uint256 i = 0; i < oracles.length; i++) {
            mellowOracles[i] = oracles[i];
        }
        numberOfMellowOracles = oracles.length;
    }

    function getOracle(address token) public view returns (address, IBaseOracle.SecurityParams memory) {
        {
            OracleData memory data = erc20Oracles[token];
            if (address(data.oracle) != address(0)) {
                return (address(data.oracle), data.params);
            }
        }
        {
            uint256 numberOfMellowOracles_ = numberOfMellowOracles;
            for (uint256 i = 0; i < numberOfMellowOracles_; i++) {
                OracleData memory data = mellowOracles[i];
                if (IMellowBaseOracle(address(data.oracle)).isTokenSupported(token)) {
                    return (address(data.oracle), data.params);
                }
            }
        }
        revert OracleNotFound();
    }

    function getOracles(
        address[] calldata tokens
    ) external view returns (address[] memory requestedOracles, IBaseOracle.SecurityParams[] memory parameters) {
        uint256 n = tokens.length;
        requestedOracles = new address[](n);
        parameters = new IBaseOracle.SecurityParams[](n);
        for (uint256 i = 0; i < n; ++i) {
            (requestedOracles[i], parameters[i]) = getOracle(tokens[i]);
        }
    }
}

