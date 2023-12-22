// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./AccessControlEnumerable.sol";
import "./IERC20.sol";
import "./IPriceConsumer.sol";

interface IDIAOracleV2 {
    function getValue(string memory) external returns (uint128, uint128);
}

contract DiaPriceConsumer is IPriceConsumer, AccessControlEnumerable {
    IDIAOracleV2 private _oracle;

    bytes32 public constant ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");

    mapping(address => uint256) private _tokenPrice;
    mapping(address => uint256) private _tokenTimestamp;

    constructor(address oracle) {
        _oracle = IDIAOracleV2(oracle);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function fetchPriceInUSD(address token, uint256 minTimestamp) external override onlyRole(ORACLE_MANAGER_ROLE) {
        if (_tokenTimestamp[token] >= minTimestamp) return;
        string memory symbol = IERC20(token).symbol();
        string memory key = string(abi.encodePacked(symbol, "/USD"));
        (uint128 latestPrice, uint128 timestampOflatestPrice) = _oracle.getValue(key);
        _tokenPrice[token] = uint256(latestPrice);
        _tokenTimestamp[token] = uint256(timestampOflatestPrice);
    }

    function getPriceInUSD(address token) external view override returns (uint256, uint256) {
        return (_tokenPrice[token], _tokenTimestamp[token]);
    }
}

