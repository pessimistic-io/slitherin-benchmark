// SPDX-License-Identifier: bsl-1.1

pragma solidity ^0.8.0;

import "./ABDKMath64x64.sol";

import "./ICoreMultidataFeedsReader.sol";
import "./AbstractFeedsWithMetrics.sol";
import "./NonProxiedOwnerMultipartyCommons.sol";


/**
 * @notice Write-efficient oracle
 */
contract DeltaFeeds is ICoreMultidataFeedsReader, NonProxiedOwnerMultipartyCommons, AbstractFeedsWithMetrics {
    using ABDKMath64x64 for int128;

    /**
     * @notice Contract version, using SemVer version scheme.
     *
     * 0.2 - pre-multiparty branch
     * 0.3 - multiparty branch
     */
    string public constant override VERSION = "0.3.1";

    // Signed 64.64 fixed point number 1.002 gives us minimal distinguishable price change of 0.2%.
    int128 public constant DELTA_BASE = int128(uint128(1002 * 2 ** 64) / uint128(1000));

    // min delta is DELTA_BASE ** -512, max delta is DELTA_BASE ** 511
    uint256 public constant DELTA_BITS = 10;

    // keccak256("DeltaFeeds.deltas")
    uint256 private constant DELTAS_LOCATION = 0xe2fa74590d73fe2f2afa21f2ddf03c378ff30b2f89c8b95dfd3c290bdb4e0222;

    uint256 private constant NO_DELTA = 0;
    uint256 private constant DELTA_MODULO = 1 << DELTA_BITS;        // module for two's complement arithmetic
    uint256 private constant DELTA_MASK = DELTA_MODULO - 1;         // mask to extract a delta
    uint256 private constant DELTAS_PER_SLOT = 256 / DELTA_BITS;    // note that there may be unused bits in a slot
    uint256 private constant SLOT_PADDING_BITS = 256 - DELTAS_PER_SLOT * DELTA_BITS;    // unused bits in a slot

    int128 private constant ABDK_ONE = int128(int256(1 << 64));

    bytes32 immutable private UPDATE_TYPE_HASH;

    struct Status {
        // TODO add per-metric update timestamps
        uint32 epochId; // last unix timestamp of ANY update
    }

    Status internal status;

    uint[] internal prices;

    constructor() NonProxiedOwnerMultipartyCommons(address(this), block.chainid) {
        UPDATE_TYPE_HASH = keccak256("Update(uint32 epochId,uint32 previousEpochId,uint256[] metricIds,uint256[] basePrices,bytes deltas)");
    }

    /// @dev Status field getter.
    function getStatus() external view returns (Status memory) {
        return status;
    }

    // Exports state for updater (only!)
    function getState() external view returns (
        int128 DELTA_BASE_, uint256 DELTA_BITS_,
        uint32 epochId_,
        Metric[] memory metrics_, uint[] memory basePrices_, uint[] memory currentDeltas_
    ) {
        DELTA_BASE_ = DELTA_BASE;
        DELTA_BITS_ = DELTA_BITS;

        epochId_ = status.epochId;

        metrics_ = getMetrics();
        basePrices_ = prices;
        currentDeltas_ = new uint[](metrics_.length);
        // TODO optimize excess sload-s
        for (uint i = 0; i < currentDeltas_.length; i++)
            currentDeltas_[i] = getDelta(i);
    }


    /// @inheritdoc ICoreMultidataFeedsReader
    function quoteMetrics(string[] calldata names_) external view override returns (Quote[] memory quotes) {
        uint32 updateTS = status.epochId;
        uint256 length = names_.length;
        quotes = new Quote[](length);
        for (uint i = 0; i < length; i++) {
            (bool exists, uint id) = hasMetric(names_[i]);
            require(exists, "MultidataFeeds: METRIC_NOT_FOUND");

            // TODO optimize excess sload-s
            quotes[i] = Quote(getPrice(id), updateTS);
        }
    }

    /// @inheritdoc ICoreMultidataFeedsReader
    function quoteMetrics(uint256[] calldata ids) external view override returns (Quote[] memory quotes) {
        uint32 updateTS = status.epochId;
        uint256 length = ids.length;
        uint256 totalMetrics = getMetricsCount();
        quotes = new Quote[](length);
        for (uint i = 0; i < length; i++) {
            uint256 id = ids[i];
            require(id < totalMetrics, "MultidataFeeds: METRIC_NOT_FOUND");

            // TODO optimize excess sload-s
            quotes[i] = Quote(getPrice(id), updateTS);
        }
    }

    /// @notice Adds new metrics along with their current prices.
    /// @dev Internal implementation (it's marked external, but see selfCall)
    function addMetrics(Metric[] calldata metrics_, uint256[] calldata prices_, uint salt, uint deadline)
        external
        selfCall
        applicable(salt, deadline)
    {
        require(metrics_.length != 0 && metrics_.length == prices_.length, "MultidataFeeds: BAD_LENGTH");

        uint256 length = metrics_.length;
        for (uint256 i = 0; i < length; i++) {
            addMetric(metrics_[i]);
            prices.push(prices_[i]);
            require(getMetricsCount() == prices.length, 'MultidataFeeds: BROKEN_LOGIC');

            // no need - as we're hitting these bytes of storage for the first time - they're zeroed
            // setDelta(id, NO_DELTA);
        }
    }

    /// @notice Updates info of metrics_.
    function updateMetrics(Metric[] calldata metrics_, uint salt, uint deadline)
        external
        selfCall
        applicable(salt, deadline)
    {
        for (uint256 i = 0; i < metrics_.length; i++) {
            updateMetric(metrics_[i]);
        }
    }

    function update(uint32 epochId_, uint32 previousEpochId_, uint[] calldata metricIds_, uint256[] calldata prices_,
                    bytes calldata deltas_, uint8 v, bytes32 r, bytes32 s)
        external
    {
        checkUpdateAccess(epochId_, previousEpochId_, metricIds_, prices_, deltas_, v, r, s);

        require(epochId_ > previousEpochId_ && epochId_ <= block.timestamp, "MultidataFeeds: BAD_EPOCH");
        require(status.epochId == previousEpochId_, "MultidataFeeds: STALE_UPDATE");
        require(metricIds_.length == prices_.length, "MultidataFeeds: BAD_LENGTH");

        status.epochId = epochId_;
        bool hasDeltaUpdate = deltas_.length != 0;

        uint256 metricsCount = getMetricsCount();
        require(0 != metricsCount, "MultidataFeeds: NO_METRICS");

        if (metricIds_.length != 0) {
            // Base prices update (aka setPrice(s))
            uint256 length = metricIds_.length;
            for (uint256 i = 0; i < length; i++) {
                uint256 id = metricIds_[i];
                uint256 price = prices_[i];
                require(id < metricsCount, "MultidataFeeds: METRIC_NOT_FOUND");

                prices[id] = price;
                if (!hasDeltaUpdate)
                    setDelta(id, NO_DELTA);
            }
        }

        if (!hasDeltaUpdate) {
            emit MetricUpdated(epochId_, type(uint256).max-1);
            return;
        }

        // Updating deltas
        // deltas := [slot], [slot ...]
        // slot := delta, [delta ...], zero padding up to 256 bits
        // delta := signed DELTA_BITS-bit number, to be used as an exponent of DELTA_BASE
        uint256 slots = (metricsCount - 1) / DELTAS_PER_SLOT + 1;
        require(deltas_.length == 32 * slots, "MultidataFeeds: WRONG_LENGTH");

        // deltas offset is stored at the calldata offset:
        //      selector + uint(epochId_) + uint(previousEpochId_) + uint(metricIds_ offset) + uint(prices_ offset)
        //      == 4 + 4 * 32 == 132
        // plus, skipping the length word and selector (it's not a part of abi-coded offset)
        uint256 srcOffset;
        assembly {
            srcOffset := add(calldataload(132), 36)
        }
        // dstSlot - storage pointer
        for (uint256 dstSlot = DELTAS_LOCATION; dstSlot < DELTAS_LOCATION + slots; dstSlot++) {
            assembly {
                sstore(dstSlot, calldataload(srcOffset))
            }
            srcOffset += 32;
        }
        emit MetricUpdated(epochId_, type(uint256).max-1);
    }


    /// @dev Gets raw metric delta (signed logarithm encoded as two's complement)
    function getDelta(uint256 id) internal view returns (uint256) {
        uint256 slot = DELTAS_LOCATION + id / DELTAS_PER_SLOT;
        uint256 deltaBlock;
        assembly {
            deltaBlock := sload(slot)
        }

        // Unpack one delta from the slot contents
        return (deltaBlock >> getBitsAfterDelta(id)) & DELTA_MASK;
    }

    /// @dev Sets raw metric delta (signed logarithm encoded as two's complement)
    function setDelta(uint256 id, uint256 delta) internal {
        uint256 dstSlot = DELTAS_LOCATION + id / DELTAS_PER_SLOT;
        uint256 current;
        assembly {
            current := sload(dstSlot)
        }

        // Clear the delta & overwrite it with new content keeping others intact
        uint256 bitsAfterDelta = getBitsAfterDelta(id);
        current &= ~(DELTA_MASK << bitsAfterDelta);     // setting zeroes
        current |= delta << bitsAfterDelta;       // writing delta

        assembly {
            sstore(dstSlot, current)
        }
    }

    function getBitsAfterDelta(uint256 id) internal pure returns (uint256) {
        uint256 deltaIdx = id % DELTAS_PER_SLOT;
        return (DELTAS_PER_SLOT - 1 - deltaIdx) * DELTA_BITS + SLOT_PADDING_BITS;
    }

    function getPrice(uint256 id) internal view returns (uint256) {
        uint256 rawDelta = getDelta(id);
        int128 delta;
        if (0 == rawDelta & (1 << (DELTA_BITS - 1))) {
            // Non-negative power
            delta = DELTA_BASE.pow(rawDelta);
        }
        else {
            // Negative power, converting from two's complement
            delta = ABDK_ONE.div(DELTA_BASE.pow(DELTA_MODULO - rawDelta));
        }

        uint256 basePrice = prices[id];
        return delta.mulu(basePrice);
    }


    function checkUpdateAccess(uint32 epochId_, uint32 previousEpochId_,
                               uint256[] calldata metricIds_, uint256[] calldata prices_, bytes calldata deltas_,
                               uint8 v, bytes32 r, bytes32 s)
        internal
        virtual
        view
    {
        checkMessageSignature(keccak256(abi.encode(
                UPDATE_TYPE_HASH, epochId_, previousEpochId_,
                keccak256(abi.encodePacked(metricIds_)), keccak256(abi.encodePacked(prices_)), keccak256(deltas_)
            )),
            v, r, s);
    }
}

