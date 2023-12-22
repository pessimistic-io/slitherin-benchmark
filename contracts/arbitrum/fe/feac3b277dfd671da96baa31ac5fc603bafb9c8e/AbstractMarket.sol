// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SignatureVerifier.sol";
import "./Maths.sol";



abstract contract AbstractMarket{


    uint256 constant MULTIPLIER = 10**10;
    uint256 constant LNDENOMINATION = 5;

    struct Prediction{
        uint256 predictionTimestamp;
        bytes32 encodedPrediction;
        uint256 decodedPrediction;
        bool predicted;
        bool correct;
        bool verifiedPrediction;
    }
    string public question;
    uint256 public numberOfOutcomes;
    uint256 public creationDate;
    uint256 public wageDeadline;
    uint256 public resolutionDate;
    bool public resolved;
    uint256 public answer;
    
    mapping(address => Prediction) public predictions;

    constructor(
        string memory _question,
        uint256 _numberOfOutcomes,
        uint256 _wageDeadline,
        uint256 _resolutionDate
    ){  
        numberOfOutcomes = _numberOfOutcomes;
        creationDate = block.timestamp;
        question = _question;
        wageDeadline = _wageDeadline;
        resolutionDate = _resolutionDate;
        resolved = false;
    }

    function predict(bytes32 _encodedPrediction) external virtual{
        require(
            block.timestamp <= wageDeadline,
            "market is no longer active"
        );
        require(
            predictions[msg.sender].predicted == false,
            "user has already predicted"
        );
        predictions[msg.sender].encodedPrediction = _encodedPrediction;
        predictions[msg.sender].predictionTimestamp = block.timestamp;
        predictions[msg.sender].predicted = true;
    }

    function calculateReputation() external view returns(uint256){
        return Maths.computeReputation(
            wageDeadline,
            creationDate,
            predictions[tx.origin].predictionTimestamp,
            numberOfOutcomes
        ); 
    }

    function verifyPrediction(
        uint256 _decodedPrediction,
        bytes calldata _signature
    ) external {
        require(
            predictions[tx.origin].predicted == true,
            "user has not predicted"
        );
        require(
            predictions[tx.origin].verifiedPrediction == false,
            "you have already verified your prediction"
        );
        require(
            keccak256(abi.encodePacked(_signature)) == predictions[tx.origin].encodedPrediction,
            "submited wrong signature"
        );


        bytes32 _message = keccak256(
            abi.encodePacked(
                _decodedPrediction,
                tx.origin,
                address(this)
            )
        );
        predictions[tx.origin].verifiedPrediction = SignatureVerifier.verify(
            tx.origin,
            _message,
            _signature
        );
    }

    function resolve() external virtual returns(bool);

    function hasPredicted(address _user) external view returns(bool){
        return predictions[_user].predicted;
    }

    function verifiedPrediction(address _user) external view returns(bool){
        return predictions[_user].verifiedPrediction;
    }

    function _getMarketOutcome() public view virtual returns(uint256);
}
