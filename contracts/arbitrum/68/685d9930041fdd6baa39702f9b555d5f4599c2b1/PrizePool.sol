// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./VRFCoordinatorV2Interface.sol";
import "./VRFConsumerBaseV2.sol";
import "./VRFCoordinatorV2.sol";
import "./IERC721.sol";
import "./IERC721Enumerable.sol";
import "./Ownable.sol";
import "./IPrizeNFT.sol";
import "./PrizeFactory.sol";

contract PrizePool is VRFConsumerBaseV2, Ownable {
    uint8 public constant NORMAL_MODE_MAX_MINT = 10;

    uint8 public constant FREEZE_MODE_MAX_MINT = 5;

    uint32 public constant FREEZE_MODE_DURATION = 5 minutes;

    uint256 public constant FEE_DECIMAL_PRECISION = 10000;

    uint256 public constant NORMAL_MODE_FEE = 500; //5%
    uint256 public constant FREEZE_MODE_FEE = 700; //7%
    uint256 public constant FEE_MAX_DISCOUNT = 200; //2%

    IPrizeNFT public immutable token;

    // 0.005 ETH
    uint256 public singleBet;

    // 1 days
    uint256 public betDuration;

    uint256 public startTime;

    //user => last mint timestamp
    mapping(address => uint256) public userLastMintTimestamp;

    address public treasury;

    //chainlink VRF
    // address public constant MAINNET_COORDINATOR = 0x41034678D6C633D8a95c75e1138A360a28bA15d1;
    // address public constant GOERLI_COORDINATOR = 0x6D80646bEAdd07cE68cab36c27c626790bBcf17f;
    VRFCoordinatorV2Interface public coordinator;

    // subscription ID.
    uint64 public s_subscriptionId;

    //mainnet 2gwei key Hash: 0x08ba8f62ff6c40a58877a106147661db43bc58dabfb814793847a839aa03367f
    //goerli 50 gwei Key Hash: 0x83d1b6e3388bed3d76426974512bb0d270e9542a765cd667242ea26c0cc0b730
    bytes32 public keyHash;

    uint16 requestConfirmations = 3;

    uint32 public callbackGasLimit = 2500000;

    // Set the number of random values to be retrieved.
    // Cannot exceed VRFCoordinatorV2.MAX_NUM_WORDS.
    uint32 public totalNumWords;

    uint32 public callbackNumwords;

    uint32 public randomStep = 80;

    uint32 public step;
    // requestId => RandomStruct
    mapping(uint256 => RandomStruct) requestMap;

    struct RandomStruct {
        uint32 stepIndex;
        uint32 totalStep;
        uint32 numWords;
        bool fulfill;
        // uint256[] winners;
    }

    // bool public fulfilled;

    uint256[] public winners;
    // tokenId => weight
    mapping(uint256 => uint256) public winnersMap;

    uint256 public perNFTReward;

    //indexId => claimed
    mapping(uint256 => bool) public claimMap;

    PrizeFactory.PoolType public poolType;

    event Mint(
        address indexed user,
        uint8 amount,
        uint256 fee,
        uint256 ethValue
    );

    event HoldLottery(
        address indexed user,
        PrizeFactory.PoolType poolType,
        uint256 requestId,
        uint32 numWords
    );

    event RequestFulfilled(uint256 indexed _requestId, uint256[] _randomWords);

    event ClaimReward(
        address indexed user,
        uint256 balanceOf,
        uint256 claimAmount
    );

    constructor(
        PrizeFactory.PoolType _poolType,
        IPrizeNFT _token,
        uint256 _singleBet,
        uint256 _betDuration,
        address _treasury,
        uint64 subscriptionId,
        address _coordinator,
        bytes32 _keyHash,
        uint256 _startTime
    ) VRFConsumerBaseV2(_coordinator) {
        poolType = _poolType;
        token = _token;
        singleBet = _singleBet;
        betDuration = _betDuration;
        treasury = _treasury;
        s_subscriptionId = subscriptionId;
        coordinator = VRFCoordinatorV2Interface(_coordinator);
        keyHash = _keyHash;
        if (_startTime == 0) {
            startTime = block.timestamp;
        } else {
            startTime = _startTime;
        }
    }

    function mint(uint8 _amount) public payable {
        require(startTime > 0, "has not started");
        require(
            block.timestamp > startTime &&
                block.timestamp < startTime + betDuration,
            "not in the betting internal"
        );

        require(callbackNumwords == 0, "in the lottery");

        address msgSender = msg.sender;
        uint256 lastMintTime = userLastMintTimestamp[msgSender];
        bool isNormalMode = block.timestamp - lastMintTime >
            FREEZE_MODE_DURATION;
        if (isNormalMode) {
            require(_amount <= NORMAL_MODE_MAX_MINT, "normal amount exceed");
        } else {
            require(_amount <= FREEZE_MODE_MAX_MINT, "freeze amount exceed");
        }
        userLastMintTimestamp[msgSender] = block.timestamp;

        require(msg.value >= singleBet * _amount, "send eth error");

        uint256 fee = 0;
        uint256 perDiscount = 20; //0.2%
        if (isNormalMode) {
            uint256 discount = _amount * perDiscount;
            fee = discount >= FEE_MAX_DISCOUNT
                ? NORMAL_MODE_FEE - FEE_MAX_DISCOUNT
                : NORMAL_MODE_FEE - discount;
        } else {
            uint256 discount = _amount * perDiscount;
            fee = discount >= FEE_MAX_DISCOUNT
                ? FREEZE_MODE_FEE - FEE_MAX_DISCOUNT
                : FREEZE_MODE_FEE - discount;
        }

        uint256 feeResult = (msg.value * fee) / FEE_DECIMAL_PRECISION;
        if (feeResult > 0) {
            sendEther(payable(treasury), feeResult);
        }

        for (uint8 i = 0; i < _amount; i++) {
            token.safeMint(msgSender);
        }
        emit Mint(msgSender, _amount, fee, msg.value);
    }

    function getTotalRandomNumber() public view returns (uint32) {
        uint256 totalSupply = IERC721Enumerable(token).totalSupply();
        require(totalSupply > 0, "totalSupply is zero");

        uint32 tempNumWords = 0;
        if (poolType == PrizeFactory.PoolType.ChosenOne) {
            tempNumWords = 1;
        } else if (poolType == PrizeFactory.PoolType.TenPercent) {
            tempNumWords = uint32(uint256(totalSupply / 10));
        } else if (poolType == PrizeFactory.PoolType.FiftyPercent) {
            tempNumWords = uint32(uint256(totalSupply / 2));
        }
        //VRFCoordinatorV2.MAX_NUM_WORDS = 500
        if (tempNumWords > 500) {
            tempNumWords = 500;
        }
        if (tempNumWords == 0) {
            tempNumWords = 1;
        }
        return tempNumWords;
    }

    // To hold a lottery
    function holdLottery() public returns (uint256) {
        require(
            block.timestamp > startTime + betDuration,
            "not in the lottery"
        );
        require(step == 0, "already fulfill");

        totalNumWords = getTotalRandomNumber();

        step = (totalNumWords + randomStep - 1) / randomStep;
        for (uint32 i = 0; i < step; i++) {
            uint32 numWords = 0;
            if (totalNumWords > (i + 1) * randomStep) {
                numWords = randomStep;
            } else {
                numWords = totalNumWords - i * randomStep;
            }
            require(numWords > 0, "numWords is zero");
            // Will revert if subscription is not set and funded.
            uint256 requestId = coordinator.requestRandomWords(
                keyHash,
                s_subscriptionId,
                requestConfirmations,
                callbackGasLimit,
                numWords
            );
            requestMap[requestId] = RandomStruct({
                stepIndex: i,
                totalStep: step,
                numWords: numWords,
                fulfill: false
            });
        }
        // emit HoldLottery(msg.sender, poolType, requestId, numWords);
        return step;
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        require(requestMap[_requestId].numWords > 0, "request not found");
        requestMap[_requestId].fulfill = true;
        uint256 length = _randomWords.length;
        require(
            length == uint256(requestMap[_requestId].numWords),
            "length not equal"
        );
        callbackNumwords += uint32(length);
        uint256 totalSupply = IERC721Enumerable(token).totalSupply();
        for (uint256 i = 0; i < length; i++) {
            uint256 random = _randomWords[i] % totalSupply;
            winners.push(random);
        }
        if (callbackNumwords == totalNumWords) {
            perNFTReward = address(this).balance / totalNumWords;
        }
        // emit RequestFulfilled(_requestId, _randomWords);
    }

    function claimReward(address user) public {
        if (perNFTReward == 0) {
            return;
        }

        uint256 balanceOf = IERC721(token).balanceOf(user);
        if (balanceOf == 0) {
            return;
        }
        if (callbackNumwords != totalNumWords) {
            // in lottery
            return;
        }
        if (winners.length == 0) {
            return;
        }
        if (winnersMap[winners[0]] == 0) {
            for (uint256 i = 0; i < winners.length; i++) {
                uint256 tokenId = winners[i];
                winnersMap[tokenId] = winnersMap[tokenId] + 1;
            }
        }

        uint claimAmount = 0;
        for (uint256 i = 0; i < balanceOf; i++) {
            uint256 tokenId = IERC721Enumerable(token).tokenOfOwnerByIndex(
                user,
                i
            );
            uint256 weight = winnersMap[tokenId];
            if (weight > 0) {
                if (!claimMap[tokenId]) {
                    claimMap[tokenId] = true;
                    claimAmount += perNFTReward * weight;
                }
            }
        }
        if (claimAmount == 0) {
            return;
        }
        sendEther(payable(user), claimAmount);
        emit ClaimReward(user, balanceOf, claimAmount);
    }

    function sendEther(address payable _to, uint256 _amount) internal {
        require(_amount <= address(this).balance, "eth: insufficient exceed");
        (bool sent, ) = _to.call{value: _amount}("");
        require(sent, "failed to send Ether, recepient may have reverted");
    }

    function getWinnersLength() public view returns (uint256) {
        return winners.length;
    }

    function getClaimAmount(
        bool filterClaimed
    ) public view returns (uint256 claimAmount) {
        require(perNFTReward > 0, "reward error");

        uint256 balanceOf = IERC721(token).balanceOf(msg.sender);
        require(balanceOf > 0, "you don't have PrizeNFT");
        for (uint256 i = 0; i < balanceOf; i++) {
            uint256 tokenId = IERC721Enumerable(token).tokenOfOwnerByIndex(
                msg.sender,
                i
            );
            uint256 tokenIdWeight = 0;
            for (uint256 j = 0; j < winners.length; j++) {
                uint256 random = winners[j];
                if (tokenId == random) {
                    tokenIdWeight = tokenIdWeight + 1;
                }
            }
            if (tokenIdWeight > 0) {
                if (filterClaimed) {
                    if (!claimMap[tokenId]) {
                        claimAmount += perNFTReward * tokenIdWeight;
                    }
                } else {
                    claimAmount += perNFTReward * tokenIdWeight;
                }
            }
        }
    }

    function getFee(uint8 _amount) public view returns (uint256 fee) {
        uint256 lastMintTime = userLastMintTimestamp[msg.sender];
        bool isNormalMode = block.timestamp - lastMintTime >
            FREEZE_MODE_DURATION;
        uint256 perDiscount = 20; //0.2%
        if (isNormalMode) {
            uint256 discount = _amount * perDiscount;
            fee = discount >= FEE_MAX_DISCOUNT
                ? NORMAL_MODE_FEE - FEE_MAX_DISCOUNT
                : NORMAL_MODE_FEE - discount;
        } else {
            uint256 discount = _amount * perDiscount;
            fee = discount >= FEE_MAX_DISCOUNT
                ? FREEZE_MODE_FEE - FEE_MAX_DISCOUNT
                : FREEZE_MODE_FEE - discount;
        }
    }

    function getCurrentTime() public view returns (uint256) {
        return block.timestamp;
    }

    function setCallbackGasLimit(uint32 _callbackGasLimit) public onlyOwner {
        callbackGasLimit = _callbackGasLimit;
    }

    function setKeyHash(bytes32 _keyHash) public onlyOwner {
        keyHash = _keyHash;
    }

    function setRandomStep(uint32 _randomStep) public onlyOwner {
        randomStep = _randomStep;
    }

    function resetLotteryParams() public onlyOwner {
        for (uint256 i = 0; i < winners.length; i++) {
            delete winnersMap[winners[i]];
        }
        step = 0;
        callbackNumwords = 0;
        delete winners;
        perNFTReward = 0;
    }

    receive() external payable {}

}

