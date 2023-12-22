// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.23;

import "./OwnableUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./IChainlinkLowLatencyOracleBase.sol";

abstract contract ChainlinkLowLatencyOracleBase is IChainlinkLowLatencyOracleBase, OwnableUpgradeable, AccessControlUpgradeable {

    bytes32 public constant EXECUTOR_ROLE = keccak256('EXECUTOR_ROLE');
    bytes32 public constant feedLabelStrHash = keccak256(abi.encodePacked("feedIDStr"));
    bytes32 public constant feedLabelHexHash = keccak256(abi.encodePacked("feedIDHex"));
    bytes32 public constant blockNumberQueryLabelHash = keccak256(abi.encodePacked("BlockNumber"));
    bytes32 public constant timestampQueryLabelHash = keccak256(abi.encodePacked("Timestamp"));

    OracleLookupData public oracleLookupData;
    IVerifierProxy public verifier;

    modifier onlyValidLookupData(OracleLookupData calldata _oracleLookupData) {
        bytes32 oracleLookupFeedLabel = keccak256(abi.encodePacked(_oracleLookupData.feedLabel));
        bytes32 oracleLookhapQueryLabelHash = keccak256(abi.encodePacked(_oracleLookupData.queryLabel));

        require(oracleLookupFeedLabel == feedLabelStrHash || oracleLookupFeedLabel == feedLabelHexHash, "Invalid feed label");
        require(_oracleLookupData.feeds.length > 0, "Feeds array is empty");
        require(oracleLookhapQueryLabelHash == blockNumberQueryLabelHash || oracleLookhapQueryLabelHash == timestampQueryLabelHash, "Invalid query label");

        _;
    }

    function __ChainlinkLowLatencyOracleBase_init(address _owner, OracleLookupData calldata _oracleLookupData, IVerifierProxy _verifier) internal onlyInitializing onlyValidLookupData(_oracleLookupData) {
        OwnableUpgradeable.__Ownable_init();
        AccessControlUpgradeable.__AccessControl_init();

        _transferOwnership(_owner);
        _setupRole(DEFAULT_ADMIN_ROLE, _owner);

        verifier = _verifier;
        oracleLookupData = OracleLookupData({
            feedLabel: _oracleLookupData.feedLabel,
            feeds: _oracleLookupData.feeds,
            queryLabel: _oracleLookupData.queryLabel
        });
    }

    function setVerifier(IVerifierProxy _verifier) external onlyOwner {
        verifier = _verifier;
    }

    function checkUpkeep(bytes calldata _data) external view returns (bool upkeepNeeded, bytes memory performData) {
        bytes4 eventType = bytes4(_data[:4]);
        bytes memory eventData = _data[4:];
        
        (bool isEventMatch, bytes memory processedData) = performEventMatch(eventType, eventData);

        uint256 queryValue;
        bytes32 oracleLookupQueryLabelHash = keccak256(abi.encodePacked(oracleLookupData.queryLabel));

        if(oracleLookupQueryLabelHash == blockNumberQueryLabelHash) {
            queryValue = block.number;
        }
        else {
            queryValue = block.timestamp;
        }

        if(isEventMatch) {
            revert OracleLookup(oracleLookupData.feedLabel, oracleLookupData.feeds, oracleLookupData.queryLabel, queryValue, processedData);
        }

        return (false, "");
    }

    function oracleCallback(bytes[] calldata _values, bytes calldata _extraData) external pure returns (bool upkeepNeeded, bytes memory performData) {
        performData = abi.encode(_values, _extraData);
        
        return (true, performData);
    }

    function performUpkeep(bytes calldata _performData) external onlyRole(EXECUTOR_ROLE) {
        (bytes[] memory chainlinkReports, bytes memory data) = abi.decode(_performData, (bytes[], bytes));

        bytes memory verifierResponse = verifier.verify(chainlinkReports[0]);

        execute(verifierResponse, chainlinkReports, data);
    }

    function performEventMatch(bytes4 eventType, bytes memory eventData) internal view virtual returns (bool, bytes memory);
    function execute(bytes memory verifierResponse, bytes[] memory chainlinkReports, bytes memory data) internal virtual;
}
