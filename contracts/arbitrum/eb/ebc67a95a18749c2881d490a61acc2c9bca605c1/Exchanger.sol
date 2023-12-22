// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {ConfirmedOwner} from "./ConfirmedOwner.sol";
import {IExchanger} from "./IExchanger.sol";
import {IVerifierProxy} from "./IVerifierProxy.sol";
import {IERC165} from "./introspection_IERC165.sol";
import {TypeAndVersionInterface} from "./TypeAndVersionInterface.sol";
import {Strings} from "./Strings.sol";
import {ArbSys} from "./ArbSys.sol";

contract Exchanger is IExchanger, TypeAndVersionInterface, ConfirmedOwner {
    IVerifierProxy private s_verifierProxyAddress;
    bytes private s_lookupURL; // Must be accessible to client (ex. 'https://<mercury host>/')
    uint8 private s_maxDelay; // Max block delay from commitment to execution (ex. 3 blocks)
    bool private s_arbitrumChain; // Configures the contract to handle chain-specific logic

    ArbSys internal constant ARB_SYS = ArbSys(0x0000000000000000000000000000000000000064);

    mapping(bytes32 => uint256) private s_commitmentReceived;

    event TradeCommitted(bytes32 commitment);
    event TradeExecuted(
        bytes32 indexed feedId,
        bytes32 currencySrc,
        bytes32 currencyDst,
        uint256 amountSrc,
        uint256 minAmountDst,
        address indexed sender,
        address indexed receiver,
        uint32 observationsTimestamp,
        uint64 blocknumberLowerBound,
        uint64 blocknumberUpperBound,
        bytes32 upperBlockhash,
        int192 median,
        int192 bid,
        int192 ask
    );
    event SetDelay(uint8 maxDelay);
    event SetLookupURL(string url);
    event SetVerifierProxy(IVerifierProxy verifierProxyAddress);

    error OffchainLookup(
        address sender,
        string[] urls,
        bytes callData,
        bytes4 callbackFunction,
        bytes extraData
    );
    error TradeExceedsWindow(uint256 blocknumber, uint256 tradeWindow);
    error FeedIDMismatch(bytes32 reportFeedID, bytes32 commitmentFeedID);
    error BlockhashMismatch(bytes32 reportBlockhash, bytes32 upperBoundBlockhash);

    constructor(
        IVerifierProxy verifierProxyAddress,
        string memory lookupURL,
        uint8 maxDelay,
        bool arbitrumChain
    ) ConfirmedOwner(msg.sender) {
        s_verifierProxyAddress = verifierProxyAddress;
        s_lookupURL = abi.encode(lookupURL);
        s_maxDelay = maxDelay;
        s_arbitrumChain = arbitrumChain;
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
        external
        pure
        override
        returns (bool)
    {
        return
            interfaceId ==
                this.commitTrade.selector ^
                this.resolveTrade.selector ^
                this.resolveTradeWithReport.selector ^
                this.getDelay.selector ^
                this.setDelay.selector ^
                this.getLookupURL.selector ^
                this.setLookupURL.selector ^
                this.getVerifierProxyAddress.selector ^
                this.setVerifierProxyAddress.selector;
    }

    /// @inheritdoc TypeAndVersionInterface
    function typeAndVersion() external pure override returns (string memory) {
        return "Exchanger 0.0.1";
    }

    /// @inheritdoc IExchanger
    function commitTrade(bytes32 commitment) external override {
        // Commit to the last block as the report for the latest
        // block number might not be available yet in the Mercury Server
        s_commitmentReceived[commitment] = _getBlocknumber() - 1;

        // Optionally perform other protocol functions

        emit TradeCommitted(commitment);
    }

    /// @inheritdoc IExchanger
    function resolveTrade(bytes memory encodedCommitment)
        external
        view
        override
        returns (string memory)
    {
        bytes32 commitmentHash = keccak256(encodedCommitment);

        uint256 commitmentBlock = s_commitmentReceived[commitmentHash];

        Commitment memory commitment = abi.decode(
            encodedCommitment,
            (Commitment)
        );

        return _ccipReadURL(commitment.feedId, commitmentBlock);
    }

    /// @inheritdoc IExchanger
    function resolveTradeWithReport(
        bytes memory chainlinkBlob,
        bytes memory encodedCommitment
    ) external override {
        Commitment memory commitment = abi.decode(
            encodedCommitment,
            (Commitment)
        );
        bytes32 commitmentHash = keccak256(encodedCommitment);

        if (_getBlocknumber() > s_commitmentReceived[commitmentHash] + s_maxDelay)
            revert TradeExceedsWindow(
                _getBlocknumber(),
                s_commitmentReceived[commitmentHash] + s_maxDelay
            );

        bytes memory verifierResponse = IVerifierProxy(s_verifierProxyAddress)
            .verify(chainlinkBlob);

        Report memory report = abi.decode(verifierResponse, (Report));

        if (report.feedId != commitment.feedId)
            revert FeedIDMismatch(report.feedId, commitment.feedId);

        if (report.upperBlockhash != _getBlockhash(report.blocknumberUpperBound))
            revert BlockhashMismatch(report.upperBlockhash, _getBlockhash(report.blocknumberUpperBound));

        emit TradeExecuted(
            commitment.feedId,
            commitment.currencySrc,
            commitment.currencyDst,
            commitment.amountSrc,
            commitment.minAmountDst,
            commitment.sender,
            commitment.receiver,
            report.observationsTimestamp,
            report.blocknumberLowerBound,
            report.blocknumberUpperBound,
            report.upperBlockhash,
            report.median,
            report.bid,
            report.ask
        );
    }

    // Example for feedId = "ETH-USD": https://<mercury host>/?feedIDHex=0x2430f68ea2e8d4151992bb7fc3a4c472087a6149bf7e0232704396162ab7c1f7&blockNumber=1000
    function _ccipReadURL(bytes32 feedId, uint256 commitmentBlock)
        private
        view
        returns (string memory url)
    {
        return
            string(
                abi.encodePacked(
                    abi.decode(s_lookupURL, (string)),
                    "?feedIDHex=",
                    Strings.toHexString(uint256(feedId)),
                    "&blockNumber=",
                    Strings.toString(commitmentBlock)
                )
            );
    }

    /// @inheritdoc IExchanger
    function getDelay() external view override returns (uint8 maxDelay) {
        return s_maxDelay;
    }

    /// @inheritdoc IExchanger
    function setDelay(uint8 maxDelay) external override onlyOwner {
        s_maxDelay = maxDelay;
        emit SetDelay(s_maxDelay);
    }

    /// @inheritdoc IExchanger
    function getLookupURL() external view override returns (string memory url) {
        return abi.decode(s_lookupURL, (string));
    }

    /// @inheritdoc IExchanger
    function setLookupURL(string memory url) external override onlyOwner {
        s_lookupURL = abi.encode(url);
        emit SetLookupURL(url);
    }

    /// @inheritdoc IExchanger
    function getVerifierProxyAddress()
        external
        view
        override
        returns (IVerifierProxy verifierProxyAddress)
    {
        return s_verifierProxyAddress;
    }

    /// @inheritdoc IExchanger
    function setVerifierProxyAddress(IVerifierProxy verifierProxyAddress)
        external
        override
        onlyOwner
    {
        s_verifierProxyAddress = verifierProxyAddress;
        emit SetVerifierProxy(s_verifierProxyAddress);
    }

    function _getBlocknumber()
        private
        view
        returns (uint64 blockNumber)
    {
        if (s_arbitrumChain) {
            return uint64(ARB_SYS.arbBlockNumber());
        } else {
            return uint64(block.number);
        }
    }

    function _getBlockhash(uint64 blockNum)
        private
        view
        returns (bytes32 blockHash)
    {
        if (s_arbitrumChain) {
            uint256 arbiBlockNum = ARB_SYS.arbBlockNumber();
            if (blockNum >= arbiBlockNum || arbiBlockNum - blockNum > 256) {
                return "";
            } else {
                return ARB_SYS.arbBlockHash(blockNum);
            }
        } else {
            return blockhash(blockNum);
        }
    }
}


