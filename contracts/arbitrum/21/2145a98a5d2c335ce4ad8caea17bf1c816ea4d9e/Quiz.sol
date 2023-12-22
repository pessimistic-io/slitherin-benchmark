// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IQuestionData.sol";
import "./IGameController.sol";

import "./SafeMath.sol";
import "./Ownable.sol";
import "./IERC20.sol";

contract Quiz is Ownable
{
    using SafeMath for uint256;

    IGameController public GameCotrollerContract;
    IQuestionData public QuestionDataContract;
    IERC20 public TokenReward;  // CyberCredit

    mapping(address => uint256) public TimeTheNextToDoQuest;
    mapping(address => uint256) public TimeTheNextSubmit;
    mapping(address => mapping(uint256 => uint256)) public ListQuestionsUser;
    mapping(address => mapping(uint256 => uint256)) public ListResultAnswersUser;
    mapping(address => uint256) public BlockReturnDoQuestion; // suport client
    mapping(address => uint256) public BlockReturnSubmitQuestion; // suport client

    uint256 public DelayToDoQuest;  // block
    uint256 public TotalQuestionContract;
    uint256 public TotalQuestionOnDay;

    uint256 public BonusAnswerCorrect = 10e18;

    event OnDoQuestOnDay(address user, uint256 blockNumber);
    event OnResultQuestion(uint256 totalAnswerCorrect, uint256 totalBonus);

    struct Question
    {
        string Question;
        string Answer0;
        string Answer1;
        string Answer2;
        string Answer3;
    }

    constructor(IQuestionData questionDataContract, IERC20 tokenReward) 
    {
        QuestionDataContract = questionDataContract;
        TokenReward = tokenReward;

        // config
        DelayToDoQuest = 7168;
        TotalQuestionContract =  10;
        TotalQuestionOnDay = 3;
        BonusAnswerCorrect = 5461e18;
    }

    modifier isHeroNFTJoinGame()
    {
        address user = _msgSender();
        require(GameCotrollerContract.HeroNFTJoinGameOfUser(user) != 0, "Error: Invaid HeroNFT join game");
        _;
    }

    function SetGameCotrollerContract(IGameController gameCotrollerContract) public onlyOwner 
    {
        GameCotrollerContract = gameCotrollerContract;
    }

    function SetQuestionDataContract(IQuestionData newQuestionDataContract) public onlyOwner
    {
        QuestionDataContract = newQuestionDataContract;
    }

    function SetTokenReward(IERC20 newTokenReward) public onlyOwner
    {
        TokenReward = newTokenReward;
    }

    function SetDelayToDoQuest(uint256 newDelayToDoQuest) public onlyOwner
    {
        DelayToDoQuest = newDelayToDoQuest;
    }

    function SetTotalQuestionContract(uint256 newTotalQuestionContract) public onlyOwner
    {
        TotalQuestionContract = newTotalQuestionContract;
    }
    
    function SetTotalQuestionOnDay(uint256 newTotalQuestionOnDay) public onlyOwner
    {
        TotalQuestionOnDay = newTotalQuestionOnDay;
    }

    function SetBonusAnswerCorrect(uint256 newBonusAnswerCorrect) public onlyOwner
    {
        BonusAnswerCorrect = newBonusAnswerCorrect;
    }
    function DoQuestOnDay() public isHeroNFTJoinGame
    {
        address user = msg.sender;
        require(block.number > TimeTheNextToDoQuest[user], "Error To Do Quest: It's not time to ask quest");

        uint256 from1 = 0;
        uint256 to1 = TotalQuestionContract.div(TotalQuestionOnDay).sub(1);

        uint256 from2 = to1.add(1);
        uint256 to2 = from2.add(TotalQuestionContract.div(TotalQuestionOnDay).sub(1));

        uint256 from3 = to2.add(1);
        uint256 to3 = TotalQuestionContract.sub(1);

        ListQuestionsUser[user][0] = RandomNumber(0, user, from1, to1);
        ListQuestionsUser[user][1] = RandomNumber(1, user, from2, to2);
        ListQuestionsUser[user][2] = RandomNumber(2, user, from3, to3);

        TimeTheNextToDoQuest[user] = block.number.add(DelayToDoQuest);
        BlockReturnDoQuestion[user] = block.number;

        emit OnDoQuestOnDay(user, BlockReturnDoQuestion[user]);
    }

    function GetDataQuest(address user) public view returns(
        Question[] memory data,
        uint256 timeTheNextToDoQuest,
        uint256 timeTheNextSubmit,
        uint256 delayToDoQuest,
        uint256 blockReturnDoQuestion
        )
    {
        data = new Question[](TotalQuestionOnDay);

        if(TimeTheNextToDoQuest[user] > block.number)
        {
            for(uint256 indexQuestion = 0; indexQuestion < TotalQuestionOnDay; indexQuestion++)
            {
                uint256 questionNumber = ListQuestionsUser[user][indexQuestion];

                (data[indexQuestion].Question,
                data[indexQuestion].Answer0,
                data[indexQuestion].Answer1,
                data[indexQuestion].Answer2,
                data[indexQuestion].Answer3, ) = QuestionDataContract.ListQuestionsContract(questionNumber);
            }
        }
        else 
        {
            for(uint256 indexQuestion = 0; indexQuestion < TotalQuestionOnDay; indexQuestion++)
            {
                data[indexQuestion].Question = "";
                data[indexQuestion].Answer0 = "";
                data[indexQuestion].Answer1 = "";
                data[indexQuestion].Answer2 = "";
                data[indexQuestion].Answer3 = "";
            }
        }

        timeTheNextToDoQuest = (TimeTheNextToDoQuest[user] <= block.number) ? 0 : TimeTheNextToDoQuest[user].sub(block.number);
        timeTheNextSubmit = TimeTheNextSubmit[user];
        delayToDoQuest = DelayToDoQuest;
        blockReturnDoQuestion = BlockReturnDoQuestion[user];
    }

    function SubmitQuestions(uint256[] calldata results) public
    {
        address user = msg.sender;
        require(block.number > TimeTheNextSubmit[user], "Error Submit Question: It's not time to submit yet");
        require(block.number <= TimeTheNextToDoQuest[user], "Error Submit Question: submission timeout");

        uint256 totalAnswerCorrect = 0;

        (uint256 answer0, uint256 answer1, uint256 answer2) = QuestionDataContract.ListAnswerQuestions(
            ListQuestionsUser[user][0], ListQuestionsUser[user][1], ListQuestionsUser[user][2]
        );

        if(answer0 == results[0])
        {
            ListResultAnswersUser[user][0] = 1; // 1: true, 0: false;
            totalAnswerCorrect = totalAnswerCorrect.add(1);
        }

        if(answer1 == results[1])
        {
            ListResultAnswersUser[user][1] = 1; // 1: true, 0: false;
            totalAnswerCorrect = totalAnswerCorrect.add(1);
        }

        if(answer2 == results[2])
        {
            ListResultAnswersUser[user][2] = 1; // 1: true, 0: false;
            totalAnswerCorrect = totalAnswerCorrect.add(1);
        }

        if(totalAnswerCorrect > 0)
        {
            TokenReward.transfer(user, totalAnswerCorrect.mul(BonusAnswerCorrect));
        }

        TimeTheNextSubmit[user] = TimeTheNextToDoQuest[user];
        BlockReturnSubmitQuestion[user] = block.number;

        emit OnResultQuestion(totalAnswerCorrect, totalAnswerCorrect.mul(BonusAnswerCorrect));
    }

    function GetResultAnswers(address user) public view returns(
        uint256[] memory data,
        uint256 totalBonusToken,
        uint256 blockReturnSubmitQuestion
    )
    {
        data =  new uint256[](TotalQuestionOnDay);
        totalBonusToken = 0;

        for(uint256 resultAnswers = 0; resultAnswers < TotalQuestionOnDay; resultAnswers++)
        {
            data[resultAnswers] = ListResultAnswersUser[user][resultAnswers];
            if(ListResultAnswersUser[user][resultAnswers] == 1)
            {
                totalBonusToken = totalBonusToken.add(BonusAnswerCorrect);
            }
        }
        blockReturnSubmitQuestion = BlockReturnSubmitQuestion[user];
    }

    function RandomNumber(uint256 count, address user, uint256 from, uint256 to) public view returns(uint256)
    {
        uint256 seed = uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty, block.gaslimit)));
        uint256 randomHash = uint256(keccak256(abi.encodePacked(block.difficulty, block.timestamp, count, seed, user)));
        return randomHash % (to - from + 1) + from;
    }
}
