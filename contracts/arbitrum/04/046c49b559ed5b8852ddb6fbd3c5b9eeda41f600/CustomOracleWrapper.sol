// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IOracleWrapper } from "./IOracleWrapper.sol";

import { Ownable } from "./Ownable.sol";
import { Address } from "./Address.sol";
import { IPriceOracle } from "./IPriceOracle.sol";

contract CustomOracleWrapper is IOracleWrapper, Ownable {
    using Address for address;

    modifier isContract(address _addr) {
        if (_addr == address(0)) revert ZeroAddress();
        if (!_addr.isContract()) revert NotContract(_addr);
        _;
    }
    uint256 public constant ORACLE_TIMEOUT = 4 hours;

    mapping(address => address) public oracles;

    function addOracle(
        address _underlying,
        address _customOracleAddress
    ) external isContract(_customOracleAddress) onlyOwner {
        oracles[_underlying] = _customOracleAddress;

        emit NewOracle(_customOracleAddress, _underlying);
    }

    function removeOracle(address _underlying) external onlyOwner {
        delete oracles[_underlying];
    }

    function _getResponses(
        address _underlying,
        bytes calldata _flags
    ) internal view returns (OracleResponse memory response) {
        address oracle = oracles[_underlying];

        if (oracle == address(0)) {
            revert TokenIsNotRegistered(_underlying);
        }

        (response.currentPrice, response.lastPrice, response.lastUpdateTimestamp, response.decimals) = IPriceOracle(
            oracle
        ).getLatestPrice(_flags);

        response.success = !_isCorruptOracleResponse(response);
    }

    function _isCorruptOracleResponse(OracleResponse memory _response) internal view returns (bool) {
        if (_response.lastUpdateTimestamp == 0 || _response.lastUpdateTimestamp + ORACLE_TIMEOUT < block.timestamp)
            return true;

        if (_response.currentPrice == 0) return true;

        return false;
    }

    function getExternalPrice(
        address _underlying,
        bytes calldata _flags
    ) external view returns (uint256 price, uint8 decimals, bool success) {
        OracleResponse memory resp = _getResponses(_underlying, _flags);

        return (resp.currentPrice, resp.decimals, resp.success);
    }
}

