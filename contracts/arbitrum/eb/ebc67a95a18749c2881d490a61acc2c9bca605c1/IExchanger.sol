// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {IERC165} from "./introspection_IERC165.sol";
import {IVerifierProxy} from "./IVerifierProxy.sol";

interface IExchanger is IERC165 {
    struct Commitment {
        bytes32 feedId;
        bytes32 currencySrc;
        bytes32 currencyDst;
        uint256 amountSrc;
        uint256 minAmountDst;
        address sender;
        address receiver;
    }

    struct Report {
        // The feed ID the report has data for
        bytes32 feedId;
        // The time the median value was observed on
        uint32 observationsTimestamp;
        // The median value agreed in an OCR round
        int192 median;
        // The best bid value agreed in an OCR round
        int192 bid;
        // The best ask value agreed in an OCR round
        int192 ask;
        // The upper bound of the block range the median value was observed within
        uint64 blocknumberUpperBound;
        // The blockhash for the upper bound of block range (ensures correct blockchain)
        bytes32 upperBlockhash;
        // The lower bound of the block range the median value was observed within
        uint64 blocknumberLowerBound;
    }

    /**
     * @notice Allows user to commit to a trade with the current block number saved.
     * @param commitment The keccak256 hashed commitment.
     */
    function commitTrade(bytes32 commitment) external;

    /** @notice Client can call this to fetch offchain price feed report
     * from the server URL by reverting with OffchainLookup error.
     * @param encodedCommitment Encoded struct for the commitment params
     */
    function resolveTrade(bytes memory encodedCommitment) external view returns (string memory);

    /** @notice Callback for resolveTrade to resolve the trade using the
     * fetched report digest. Validates that the original commitment
     * meets all requirements before trade is executed.
     * @param chainlinkBlob Blob from the report server containing signed
     * price report for a given block.
     * @param encodedCommitment Encoded commitment details from resolveTrade.
     */
    function resolveTradeWithReport(
        bytes memory chainlinkBlob,
        bytes memory encodedCommitment
    ) external;

    /** @notice Get the maximum number of blocks that the execution block
     * can be delayed from the commitment block.
     * @return maxDelay Maximum delay in blocks
     */
    function getDelay() external view returns (uint8 maxDelay);

    /** @notice Set the maximum number of blocks that the execution block
     * can be delayed from the commitment block.
     * @param maxDelay Maximum delay in blocks
     */
    function setDelay(uint8 maxDelay) external;

    /** @notice Get the lookup URL for the server that returns price
     * report digests.
     * @return url Offchain lookup URL
     */
    function getLookupURL() external view returns (string memory url);

    /** @notice Set the lookup URL for the server that returns price
     * report digests.
     * @param url String base URL for the offchain server (ex. https://host.server/)
     */
    function setLookupURL(string memory url) external;

    /** @notice Set the Verifier Proxy Address.
     * @return verifierProxyAddress Address of the VerifierProxy contract
     */
    function getVerifierProxyAddress()
        external
        view
        returns (IVerifierProxy verifierProxyAddress);

    /** @notice Set the Verifier Proxy Address.
     * @param verifierProxyAddress Address of the VerifierProxy contract
     */
    function setVerifierProxyAddress(IVerifierProxy verifierProxyAddress)
        external;
}

