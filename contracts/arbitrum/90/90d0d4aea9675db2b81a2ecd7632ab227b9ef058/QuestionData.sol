// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./Ownable.sol";

contract QuestionData is Ownable
{
    mapping(uint256 => QuestInfo) public ListQuestionsContract;

    event EventCreateQuestion(uint256 indexQuest, string question,
        string answer0, string answer1,
        string answer2, string answer3,
        uint256 answerResult);

    struct QuestInfo
    {
        string Question;
        string Answer0;
        string Answer1;
        string Answer2;
        string Answer3;
        uint256 AnswerResult;
    }

    // only admin
    function CreateQuestion(
        uint256 indexQuest,
        string memory question,
        string memory answer0, string memory answer1,
        string memory answer2, string memory answer3,
        uint256 answerResult) public onlyOwner
    {
        require(answerResult <= 3, "invalid answer result");

        QuestInfo storage Quest = ListQuestionsContract[indexQuest];

        Quest.Question = question;
        Quest.Answer0 = answer0;
        Quest.Answer1 = answer1;
        Quest.Answer2 = answer2;
        Quest.Answer3 = answer3;
        Quest.AnswerResult = answerResult;

        emit EventCreateQuestion(indexQuest, question, answer0, answer1, answer2, answer3, answerResult);
    }

    function ListAnswerQuestions(uint256 indexQuestion0, uint256 indexQuestion1, uint256 indexQuestion2) external view 
    returns (uint256 answer0, uint256 answer1, uint256 answer2) 
    {
        answer0 = ListQuestionsContract[indexQuestion0].AnswerResult;
        answer1 = ListQuestionsContract[indexQuestion1].AnswerResult;
        answer2 = ListQuestionsContract[indexQuestion2].AnswerResult;
    }
}
