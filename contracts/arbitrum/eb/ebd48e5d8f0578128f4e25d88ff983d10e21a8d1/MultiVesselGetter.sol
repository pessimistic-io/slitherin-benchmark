// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./IVesselManager.sol";
import "./SortedVessels.sol";

/*  Helper contract for grabbing Vessel data for the front end. Not part of the core Preon system. */
contract MultiVesselGetter {
    struct CombinedVesselData {
        address owner;
        address asset;
        uint256 debt;
        uint256 coll;
        uint256 stake;
        IVesselManager.Status status;
        uint256 snapshotAsset;
        uint256 snapshotStarDebt;
    }

    IVesselManager public vesselManager;
    ISortedVessels public sortedVessels;

    constructor(IVesselManager _vesselManager, ISortedVessels _sortedVessels) {
        vesselManager = _vesselManager;
        sortedVessels = _sortedVessels;
    }

    function getMultipleSortedVessels(
        address _asset,
        int256 _startIdx,
        uint256 _count
    ) external view returns (CombinedVesselData[] memory _vessels) {
        uint256 startIdx;
        bool descend;

        if (_startIdx >= 0) {
            startIdx = uint256(_startIdx);
            descend = true;
        } else {
            startIdx = uint256(-(_startIdx + 1));
            descend = false;
        }

        uint256 sortedVesselsSize = sortedVessels.getSize(_asset);

        if (startIdx >= sortedVesselsSize) {
            _vessels = new CombinedVesselData[](0);
        } else {
            uint256 maxCount = sortedVesselsSize - startIdx;

            if (_count > maxCount) {
                _count = maxCount;
            }

            if (descend) {
                _vessels = _getMultipleSortedVesselsFromHead(
                    _asset,
                    startIdx,
                    _count
                );
            } else {
                _vessels = _getMultipleSortedVesselsFromTail(
                    _asset,
                    startIdx,
                    _count
                );
            }
        }
    }

    function _getMultipleSortedVesselsFromHead(
        address _asset,
        uint256 _startIdx,
        uint256 _count
    ) internal view returns (CombinedVesselData[] memory _vessels) {
        address currentVesselOwner = sortedVessels.getFirst(_asset);

        for (uint256 idx = 0; idx < _startIdx; ++idx) {
            currentVesselOwner = sortedVessels.getNext(
                _asset,
                currentVesselOwner
            );
        }

        _vessels = new CombinedVesselData[](_count);

        for (uint256 idx = 0; idx < _count; ++idx) {
            _vessels[idx].owner = currentVesselOwner;
            _vessels[idx].asset = _asset;
            (
                _vessels[idx].debt,
                _vessels[idx].coll,
                _vessels[idx].stake,
                _vessels[idx].status,
                /* arrayIndex */

            ) = vesselManager.getVessel(_asset, currentVesselOwner);
            (
                _vessels[idx].snapshotAsset,
                _vessels[idx].snapshotStarDebt
            ) = vesselManager.getRewardSnapshots(_asset, currentVesselOwner);

            currentVesselOwner = sortedVessels.getNext(
                _asset,
                currentVesselOwner
            );
        }
    }

    function _getMultipleSortedVesselsFromTail(
        address _asset,
        uint256 _startIdx,
        uint256 _count
    ) internal view returns (CombinedVesselData[] memory _vessels) {
        address currentVesselOwner = sortedVessels.getLast(_asset);

        for (uint256 idx = 0; idx < _startIdx; ++idx) {
            currentVesselOwner = sortedVessels.getPrev(
                _asset,
                currentVesselOwner
            );
        }

        _vessels = new CombinedVesselData[](_count);

        for (uint256 idx = 0; idx < _count; ++idx) {
            _vessels[idx].owner = currentVesselOwner;
            _vessels[idx].asset = _asset;

            (
                _vessels[idx].debt,
                _vessels[idx].coll,
                _vessels[idx].stake,
                _vessels[idx].status,
                /* arrayIndex */

            ) = vesselManager.getVessel(_asset, currentVesselOwner);

            (
                _vessels[idx].snapshotAsset,
                _vessels[idx].snapshotStarDebt
            ) = vesselManager.getRewardSnapshots(_asset, currentVesselOwner);

            currentVesselOwner = sortedVessels.getPrev(
                _asset,
                currentVesselOwner
            );
        }
    }
}


