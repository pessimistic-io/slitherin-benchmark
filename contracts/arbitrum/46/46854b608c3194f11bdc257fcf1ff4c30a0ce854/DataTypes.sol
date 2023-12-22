pragma solidity ^0.8.12;

library DataTypes {

    struct SAParams {
        uint256 bountyAmount;
        uint256 requestPaymentAmount;
        uint256 requestExpirationTime;
        string responseDataType;
        uint256 endAt;
        address competitionContractAddress;
        address stakedToken;
        uint256 stakedAmount;
        uint256 disputeStake;
        uint256 slashAmount;
    }

    struct ValidatorData {
        uint256 optOutTime;
        uint256 currentStake;
    }

    struct ModelerData {
        string modelCommitment;
        uint256 modelerSubmissionBlock;
        uint256 medianPerformanceResults;
        uint256 currentStake;
        uint256 optOutTime;
    }

    struct ModelerChallenge {
        string ipfsChallenge;
        string ipfsResponse;
        string ipfsGraded;
        string ipfsGradeDetailLink;
        uint256 performanceResult;
    }

    struct DrandProof {
        address submitter;
        uint256 round;
        bytes32 randomness;
        bytes signature;
        bytes previous_signature;
    }

    struct InferenceRequest {
        bytes32 requestId;
        uint256 requestTime;
        address consumer;
        string input;
    }

    struct InferenceResponse {
        address modeler;
        uint256 inferenceData;
        uint256 submissionTime;
    }
}
