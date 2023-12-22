// SPDX-License-Identifier: bsl-1.1

pragma solidity ^0.8.0;

import "./MerkleProof.sol";

import "./IProofFeeds.sol";
import "./ICoreMultidataFeedsReader.sol";
import "./NonProxiedOwnerMultipartyCommons.sol";
import "./AbstractFeedsWithMetrics.sol";


contract ProofFeeds is IProofFeeds, ICoreMultidataFeedsReader, NonProxiedOwnerMultipartyCommons, AbstractFeedsWithMetrics {

    /**
     * @notice Contract version, using SemVer version scheme.
     */
    string public constant override VERSION = "0.1.0";

    bytes32 public constant override MERKLE_TREE_ROOT_TYPE_HASH = keccak256("MerkleTreeRoot(uint32 epoch,bytes32 root)");

    mapping(uint => uint) internal _values;
    mapping(uint => uint32) internal _updateTSs;

    ////////////////////////

    constructor (address sourceContractAddr_, uint sourceChainId_)
        NonProxiedOwnerMultipartyCommons(sourceContractAddr_, sourceChainId_) {

    }

    ///////////////////////

    function requireValidProof(
        SignedMerkleTreeRoot memory signedMerkleTreeRoot_,
        CheckedData memory checkedData_
    ) public view override {
        require(isProofValid(signedMerkleTreeRoot_, checkedData_), "MultidataFeeds: INVALID_PROOF");
    }

    function isProofValid(
        SignedMerkleTreeRoot memory signedMerkleTreeRoot_,
        CheckedData memory checkedData_
    ) public view override returns (bool) {
        bool isSignatureValid = isMessageSignatureValid(
            keccak256(
                abi.encode(MERKLE_TREE_ROOT_TYPE_HASH, signedMerkleTreeRoot_.epoch, signedMerkleTreeRoot_.root)
            ),
            signedMerkleTreeRoot_.v, signedMerkleTreeRoot_.r, signedMerkleTreeRoot_.s
        );

        if (!isSignatureValid) {
            return false;
        }

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(
            signedMerkleTreeRoot_.epoch,
            checkedData_.metricName,
            checkedData_.metricValue,
            checkedData_.metricUpdateTs
        ))));

        return MerkleProof.verify(checkedData_.merkleTreeProof, signedMerkleTreeRoot_.root, leaf);
    }

    ////////////////////////////

    function quoteMetrics(string[] calldata names) external view override returns (Quote[] memory quotes) {
        uint length = names.length;
        quotes = new Quote[](length);

        for (uint i; i < length; i++) {
            (bool has, uint id) = hasMetric(names[i]);
            require(has, "MultidataFeeds: INVALID_METRIC_NAME");
            quotes[i] = Quote(_values[id], _updateTSs[id]);
        }
    }

    function quoteMetrics(uint256[] calldata ids) external view override returns (Quote[] memory quotes) {
        uint length = ids.length;
        quotes = new Quote[](length);

        uint metricsCount = getMetricsCount();
        for (uint i; i < length; i++) {
            uint id = ids[i];
            require(id < metricsCount, "MultidataFeeds: INVALID_METRIC");
            quotes[i] = Quote(_values[id], _updateTSs[id]);
        }
    }

    ////////////////////////////

    /**
     * @notice Upload signed value
     * @dev metric in this instance is created if it is not exists. Important: metric id is different from metric ids from other
     *      instances of ProofFeeds and MedianFeed
     */
    function setValue(SignedMerkleTreeRoot calldata signedMerkleTreeRoot_, CheckedData calldata data_) external {
        require(isProofValid(signedMerkleTreeRoot_, data_), "MultidataFeeds: INVALID_PROOF");

        (bool has, uint metricId) = hasMetric(data_.metricName);
        if (!has) {
            metricId = addMetric(Metric(data_.metricName, "", "", new string[](0)));
        }

        require(data_.metricUpdateTs > _updateTSs[metricId], "MultidataFeeds: STALE_UPDATE");

        _values[metricId] = data_.metricValue;
        _updateTSs[metricId] = data_.metricUpdateTs;
    }
}

