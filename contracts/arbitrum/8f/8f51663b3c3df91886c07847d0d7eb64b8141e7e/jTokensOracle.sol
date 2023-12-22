//SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IViewer} from "./IViewer.sol";
import {Governable} from "./Governable.sol";

abstract contract jTokensOracle is Governable {
    IViewer public viewer;
    uint128 private min;
    uint64 private lastUpdatedAt;
    uint64 private amountCollected;
    address public asset;
    address internal keeper;

    constructor(address _asset, uint128 _min, uint64 _amountCollected) {
        min = _min;
        amountCollected = _amountCollected;
        asset = _asset;
    }

    struct Price {
        uint64 p0;
        uint64 p1;
        uint64 p2;
        uint64 p3;
    }

    Price private price;

    function updatePrice() external {
        uint64 timestampNow = uint64(block.timestamp);

        if (timestampNow < lastUpdatedAt + min) {
            revert Delay();
        }

        _shiftStruct(_supplyPrice());

        lastUpdatedAt = timestampNow;
    }

    function getLatestPrice() external view returns (uint64) {
        Price memory _price = price;
        uint64 aggregate = _price.p0 + _price.p1 + _price.p2 + _price.p3;
        return aggregate / amountCollected;
    }

    function _supplyPrice() internal virtual returns (uint64);

    function _shiftStruct(uint64 _p) private {
        price.p0 = price.p1;
        price.p1 = price.p2;
        price.p2 = price.p3;
        price.p3 = _p;
    }

    function _onlyKeeper() internal view {
        if (msg.sender != keeper) {
            revert OnlyKeeper();
        }
    }

    function _validate(address _contract) private pure {
        if (_contract == address(0)) {
            revert ZeroAddress();
        }
    }

    function setViewer(address _viewer) external onlyGovernor {
        _validate(_viewer);
        viewer = IViewer(_viewer);
    }

    function setKeeper(address _keeper) external onlyGovernor {
        _validate(_keeper);
        keeper = _keeper;
    }

    error ZeroAddress();
    error Delay();
    error OnlyKeeper();
}

