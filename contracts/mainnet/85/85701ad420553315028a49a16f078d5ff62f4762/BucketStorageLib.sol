// SPDX-License-Identifier: MIT
// Copyright 2022 PROOF Holdings Inc
pragma solidity >=0.8.16 <0.9.0;

import {IBucketStorage} from "./IBucketStorage.sol";
import {InflateLibWrapper, Compressed} from "./InflateLibWrapper.sol";
import {IndexedBucketLib} from "./IndexedBucketLib.sol";
import {LabelledBucketLib} from "./LabelledBucketLib.sol";

/**
 * @notice Coordinates to identify a bucket inside a storage bundle.
 * @dev These describe a hierarchical storage structure akin to
 * `x.storageId.bucketId`
 */
struct BucketCoordinates {
    uint256 storageId;
    uint256 bucketId;
}

/**
 * @notice Utility library to retrieve data from a storage bundle.
 */
library BucketStorageLib {
    using InflateLibWrapper for Compressed;

    /**
     * @notice Retrieves uncompressed bucket data from a bundle.
     */
    function loadUncompressed(
        IBucketStorage[] storage bundle,
        BucketCoordinates memory coordinates
    ) internal view returns (bytes memory) {
        return loadCompressed(bundle, coordinates).inflate();
    }

    /**
     * @notice Retrieves compressed bucket data from a bundle.
     */
    function loadCompressed(
        IBucketStorage[] storage bundle,
        BucketCoordinates memory coordinates
    ) internal view returns (Compressed memory) {
        return bundle[coordinates.storageId].getBucket(coordinates.bucketId);
    }
}

