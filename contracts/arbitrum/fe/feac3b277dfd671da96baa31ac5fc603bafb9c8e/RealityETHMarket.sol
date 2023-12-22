// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AbstractMarket.sol";
import "./RealityETH.sol";
import "./PythiaFactory.sol";



contract RealityETHMarket is AbstractMarket{
    uint32 timeout;
    uint256 nonce;
    uint256 min_bond;
    address arbitrator;
    RealityETH_v3_0 realityETH;
    bytes32 realityETHQuestionId;
    uint256 template_id;
    PythiaFactory pythiaFactory;

    constructor(
        address _factoryContractAddress,
        string memory _question,
        uint256 _numberOfOutcomes,
        uint256 _wageDeadline,
        uint256 _resolutionDate,
        uint256 _template_id,
        address _arbitrator,
        uint32 _timeout,
        uint256 _nonce,
        address _realityEthAddress,
        uint256 _min_bond
    ) AbstractMarket(
        _question,
        _numberOfOutcomes,
        _wageDeadline,
        _resolutionDate
    )
    { 
        template_id = _template_id;
        arbitrator = _arbitrator;
        timeout = _timeout;
        realityETH = RealityETH_v3_0(_realityEthAddress);
        pythiaFactory = PythiaFactory(_factoryContractAddress);
        min_bond = _min_bond;
        nonce = _nonce;

        realityETHQuestionId = realityETH.askQuestionWithMinBond(
            template_id,
            question,
            arbitrator,
            timeout,
            uint32(resolutionDate),
            nonce,
            min_bond
        );
    }

    function predict(bytes32 _encodedPrediction) external override{
        require(
            block.timestamp <= wageDeadline,
            "market is not active"
        );
        require(pythiaFactory.isUser(msg.sender), "user is not registered");
        require(predictions[msg.sender].predicted == false, "user has already predicted");
        predictions[msg.sender].encodedPrediction = _encodedPrediction;
        predictions[msg.sender].predictionTimestamp = block.timestamp;
        predictions[msg.sender].predicted = true;
        //log prediction event
        pythiaFactory.logNewPrediction(
            msg.sender,
            address(this),
            _encodedPrediction,
            block.timestamp
        );
    }

    function resolve() external override returns(bool){
        require(
            block.timestamp > resolutionDate,
            "resolution date has not arrived yet"
        );
        answer = _getMarketOutcome();
        resolved = true;
        pythiaFactory.logMarketResolved(
            address(this)
        );
    }

    function _getMarketOutcome() public view override returns(uint256){
        return uint256(realityETH.resultFor(realityETHQuestionId));
    }
}
