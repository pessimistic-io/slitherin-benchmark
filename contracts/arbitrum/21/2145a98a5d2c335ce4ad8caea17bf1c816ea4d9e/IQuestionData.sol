// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IQuestionData
{
    function ListQuestionsContract(uint256 indexQuest) external pure returns(
        string memory question,
        string memory answer0,
        string memory answer1,
        string memory answer2,
        string memory answer3,
        uint256 answerResult
    );

    function ListAnswerQuestions(uint256 indexQuestion0, uint256 indexQuestion1, uint256 indexQuestion2) external view 
    returns (uint256 answer0, uint256 answer1, uint256 answer2); 
} 
