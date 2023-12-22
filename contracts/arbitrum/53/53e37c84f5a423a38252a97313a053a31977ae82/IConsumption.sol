
pragma solidity ^0.8.12;

import "./DataTypes.sol";

interface IConsumption {

    event DepositPaymentToken(address indexed consumer, uint256 amount);
    event ConsumerRequestMade(address indexed consumer, bytes32 requestId);
    event InferenceSubmitted(address indexed modeler, bytes32 indexed requestId, string inference);
    event InferenceLinkSubmitted(address indexed modeler, bytes32 indexed requestId, string link);
    //event InferenceDisputed(address indexed disputer, bytes32 indexed requestId, string inferenceOrLink);

    function competitionContract() external view returns (address);
    function paymentToken() external view returns (address);
    function numberRequests() external view returns (uint256);
    function consumptionWindow() external view returns (bool);
    function consumerBalances(address consumer) external view returns (uint256);
    function inferenceRequests(bytes32 requestId) external view returns (DataTypes.InferenceRequest memory);
    function inferenceResponses(bytes32 requestId) external view returns (DataTypes.InferenceResponse[] memory);
    function modelerHasResponded(address modeler, bytes32 requestId) external view returns (bool);
    //function inferenceDisputes(bytes32 requestId) external view returns (DataTypes.InferenceDispute memory);

    function makeConsumerRequest(string calldata _input) external;
    function submitInference(bytes32 requestId, string calldata _inference) external;
    function submitInferenceLink(bytes32 requestId, string calldata _link) external;
    function getAllResponses(bytes32 _requestId) external view returns (DataTypes.InferenceResponse[] memory);
    function punishSlowModeler(address modeler, bytes32 requestId) external;
    function disputeInference(bytes32 _requestId, address _modeler, string calldata _inferenceOrLink) external;
    function handleInferenceDispute(bytes32 _requestId, bool malicious) external;
    function getDisputeStatus(bytes32 _requestId) external view returns (bool);
    function toggleConsumptionWindow(bool toggle) external;
    function depositPaymentToken(uint256 amount) external;
    function withdrawPaymentToken() external;
    function getConsumerBalance(address _consumer) external view returns (uint256);
}
