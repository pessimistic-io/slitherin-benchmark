// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./IOracleEntry.sol";
import "./IOracleAdapter.sol";
import "./IAddressManager.sol";
import "./IACLManager.sol";

contract OracleEntry is IOracleEntry {
    uint8 public constant TARGET_DECIMALS = 18;

    IAddressManager public addressManager;

    mapping(DataSource => address) public adapters;

    modifier onlyCegaAdmin() {
        require(
            IACLManager(addressManager.getACLManager()).isCegaAdmin(msg.sender),
            "OracleEntry: not cega admin"
        );
        _;
    }

    constructor(IAddressManager _addressManager) {
        addressManager = _addressManager;
    }

    function getSinglePrice(
        address asset,
        uint64 timestamp,
        DataSource dataSource
    ) external view returns (uint256) {
        return _getAdapter(dataSource).getSinglePrice(asset, timestamp);
    }

    function getPrice(
        address baseAsset,
        address quoteAsset,
        uint64 timestamp,
        DataSource dataSource
    ) external view returns (uint256) {
        return
            _getAdapter(dataSource).getPrice(baseAsset, quoteAsset, timestamp);
    }

    function setDataSourceAdapter(
        DataSource dataSource,
        address adapter
    ) external onlyCegaAdmin {
        adapters[dataSource] = adapter;

        emit DataSourceAdapterSet(dataSource, adapter);
    }

    function getTargetDecimals() external pure returns (uint8) {
        return TARGET_DECIMALS;
    }

    function _getAdapter(
        DataSource dataSource
    ) private view returns (IOracleAdapter) {
        address adapter = adapters[dataSource];
        require(adapter != address(0), "OracleEntry: unavailable data source");
        return IOracleAdapter(adapter);
    }
}

