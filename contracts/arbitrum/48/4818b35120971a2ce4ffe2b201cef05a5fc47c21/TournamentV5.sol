// --no verify
// SPDX-License-Identifier: MIT

pragma solidity =0.8.17;
pragma experimental ABIEncoderV2;

import "./ReentrancyGuard.sol";
import "./SafeERC20.sol";
import "./ECDSA.sol";
import "./Ownable.sol";
import "./ERC20_IERC20.sol";
import "./IGamePolicy.sol";
import "./IPrizeManagerV2.sol";
import "./ITournamentV5.sol";
import "./IJackpot.sol";

contract TournamentV5 is ReentrancyGuard, ITournamentV5, Ownable {
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    enum GAME_STATUS {PENDING, AVAILABLE, CLOSED, CANCELED}
    enum ROUND_RESULT {UNDEFINED, DOWN, UP, DRAW}
    struct GameInfo {
        uint256 maxPlayers;
        uint256 minPlayers;
        uint256 maxRounds;
        address targetToken;
        address buyInToken;
        uint256 buyInAmount;
        uint256 currentRoundNumber;
        uint256 startTime;
        uint256 nPlayers;
        address[] players;
        GAME_STATUS status;
        address creator;
    }

    struct RoundInfo {
        uint256 startTime;
        ROUND_RESULT result; // 1: down | 2: up | 3: draw
        uint256 players;
        uint256 predictions; // 0: down | 1 : up
        uint256 recordedAt;
    }

    struct GameResult {
        address[] winners;
        address proposer;
    }

    struct SponsorInfo {
        uint256 totalSponsors;
        address[] tokens;
        uint256[] amounts;
        address[] sponsors;
    }

    // gameId => gameInfo
    mapping (uint256 => GameInfo) public gameInfo;
    // gameId => roundId => roundInfo
    mapping (uint256 => mapping (uint256 => RoundInfo)) public roundInfo;
    // gameId => gameResult
    mapping(uint256 => GameResult) public gameResult;
    // gameId => roundId => user => prediction
    // 1: down | 2: up
    mapping(uint256 => mapping (uint256 => mapping(address => uint256))) public userPredictions;
    // gameId => roundId => isHasData
    mapping(uint256 => mapping (uint256 => bool)) public isHasData;
    // address => gameId => status
    mapping(address => mapping(uint256 => bool)) public isJoinedGame;
    // gameID => sponsorInfo
    mapping(uint256 => SponsorInfo) public sponsorInfo;

    // token => amount
    mapping (address => uint256) public minBuyIn;


    IGamePolicy public gamePolicy;
    IPrizeManagerV2 public prizeManager;
    address public feeReceiver;
    address public creationFeeToken;
    uint256 public creationFeeAmount;
    uint256 public currentGameId;
    uint256 public winingFeePercent;
    uint256 public operationFeeRatio;
    uint256 public creatorFeeRatio;
    uint256 public consolationPercent;
    uint256 public minCreationFeeAmount;
    uint256 public constant MAX_PLAYERS = 100;
    uint256 public constant MIN_PLAYERS = 50;
    uint256 public constant MAX_ROUNDS = 20;
    uint256 public constant ROUND_DURATION = 60; // 60s
    uint256 public constant DELAY_TIME = 30;
    uint256 public constant ONE_HUNDRED_PERCENT = 10000;
    uint256 public constant BASE_RATIO = 1000;

    /* ========== MODIFIERS ========== */

    modifier onlyOperator {
        require(gamePolicy.isOperator(msg.sender), "PredictionV5: !operator");
        _;
    }

    /* ========== CONSTRUCTOR ========== */

    constructor (IGamePolicy _gamePolicy, IPrizeManagerV2 _prizeManager, address _feeReceiver, uint256 _currentGameId) {
        gamePolicy = _gamePolicy;
        prizeManager = _prizeManager;
        feeReceiver = _feeReceiver;
        currentGameId = _currentGameId;
        minCreationFeeAmount = 10e18;
    }

    /* ========== VIEWS ========== */

    function getUsersAlive(uint256 _gameId, uint256 _roundId) external view returns (address[] memory) {
    }

    function getMinBuyIn(address _token) external view returns (uint256) {
        return minBuyIn[_token];
    }


    /* ========== PUBLIC FUNCTIONS ========== */

    function create(
        uint256 _maxPlayers,
        uint256 _minPlayers,
        uint256 _maxRounds,
        address _targetToken,
        address _buyInToken,
        uint256 _buyInAmount,
        uint256 _startTime
    ) external {
        _startTime = ((_startTime - 1) / 60 + 1) * 60;
        require(_startTime > block.timestamp, "PredictionV5: !startTime");
        require(gamePolicy.isTargetToken(_targetToken), "PredictionV5: !target token");
        require(gamePolicy.isBuyInToken(_buyInToken), "PredictionV5: !buyIn token");
        require( _buyInAmount >= minBuyIn[_buyInToken], "PredictionV3: !minBuyIn");
        address[] memory _new;
        currentGameId++;
        GameInfo memory _gameInfo = GameInfo (
            _maxPlayers > 0 ? _maxPlayers : MAX_PLAYERS,
            _minPlayers > 0 ? _minPlayers : MIN_PLAYERS,
            _maxRounds > 0 ? _maxRounds : MAX_ROUNDS,
            _targetToken,
            _buyInToken,
            _buyInAmount,
            0,
            _startTime,
            0,
            _new,
            block.timestamp < _startTime ? GAME_STATUS.PENDING : GAME_STATUS.AVAILABLE,
            msg.sender
        );
        gameInfo[currentGameId] = _gameInfo;
        if (creationFeeToken != address (0) && creationFeeAmount > 0) {
            IERC20(creationFeeToken).safeTransferFrom(msg.sender, feeReceiver, creationFeeAmount);
        }
        emit NewGameCreated(currentGameId);
    }

    function join(uint256 _gameId) external nonReentrant {
        GameInfo storage _gameInfo = gameInfo[_gameId];
        require(_gameInfo.status == GAME_STATUS.PENDING && _gameInfo.startTime > block.timestamp, "PredictionV5: started");
        require(!isJoinedGame[msg.sender][_gameId], "PredictionV5: joined");
        require(_gameInfo.nPlayers < _gameInfo.maxPlayers, "PredictionV5: enough player");

        IERC20(_gameInfo.buyInToken).safeTransferFrom(msg.sender, address(this), _gameInfo.buyInAmount);
        isJoinedGame[msg.sender][_gameId] = true;
        uint256 _index = _gameInfo.nPlayers;
        _gameInfo.nPlayers++;
        _gameInfo.players.push(msg.sender);
        address _jackpot = gamePolicy.getJackpotAddress();
        if (_jackpot != address(0)) {
            IJackpot(_jackpot).newTicket(msg.sender);
        }
        emit NewPlayer(_gameId, msg.sender, _index);
    }

    function sponsor(uint256 _gameId, address _token, uint256 _amount) external {
        require(gameInfo[_gameId].status == GAME_STATUS.PENDING, "PredictionV5: game started");

        SponsorInfo storage _sponsorInfo = sponsorInfo[_gameId];
        uint256 _limit = gamePolicy.getSponsorLimit(_token);
        require(_limit > 0 && _amount >= _limit, "PredictionV5: !sponsor");
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        _sponsorInfo.tokens.push(_token);
        _sponsorInfo.amounts.push(_amount);
        _sponsorInfo.sponsors.push(msg.sender);
        _sponsorInfo.totalSponsors++;
        emit Sponsored(_gameId, _token, _amount, msg.sender);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _approveTokenIfNeeded(address _token) internal {
        if (IERC20(_token).allowance(address(this), address(prizeManager)) == 0) {
            IERC20(_token).safeApprove(address(prizeManager), type(uint256).max);
        }
    }

    function _prefixed(bytes32 _hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _hash));
    }

    // option:
    //  - 1: not start
    //  - 2: normal
    //  - 3: consoled

    function _finishGame(uint256 _gameId, address[] memory _winners, uint256 _option) internal {
        GameInfo storage _gameInfo = gameInfo[_gameId];
        require(_gameInfo.status == GAME_STATUS.AVAILABLE || _gameInfo.status == GAME_STATUS.PENDING, "PredictionV5: !available");
        _gameInfo.status = _option == 1 ? GAME_STATUS.CANCELED : GAME_STATUS.CLOSED;

        GameResult storage _gameResult = gameResult[_gameId];
        _gameResult.winners = _winners;
        _gameResult.proposer = msg.sender;
        _createPrize(_gameId, _winners, msg.sender, _option);
    }

    function _createPrize(uint256 _gameId, address[] memory _winners, address _proposer, uint256 _option) internal {
        GameResult storage _gameResult = gameResult[_gameId];
        GameInfo memory _gameInfo = gameInfo[_gameId];
        _gameResult.winners = _winners;
        _gameResult.proposer = _proposer;

        uint256 _totalBuyIn = _gameInfo.buyInAmount * _gameInfo.nPlayers;

        if (_option == 1) {
            IERC20(_gameInfo.buyInToken).safeTransfer(address(prizeManager), _totalBuyIn);
            prizeManager.createPrize(_gameId, _winners, _gameInfo.buyInToken, _gameInfo.buyInAmount);
        }
        if (_option == 2 || _option == 3) {
            uint256 _feePercent = winingFeePercent;
            if (_option == 3) {
                _feePercent = ONE_HUNDRED_PERCENT - consolationPercent;
            }
            uint256 _fee = _totalBuyIn * _feePercent / ONE_HUNDRED_PERCENT;
            uint256 _prizeAmount = (_totalBuyIn - _fee) / _winners.length;
            IERC20(_gameInfo.buyInToken).safeTransfer(address(prizeManager), _totalBuyIn - _fee);
            prizeManager.createPrize(_gameId, _winners, _gameInfo.buyInToken, _prizeAmount);
            _transferSystemFee(_gameInfo.buyInToken, _fee, _gameInfo.creator);

            if (sponsorInfo[_gameId].totalSponsors > 0) {
                uint256[] memory _sizePrizeAmounts = new uint256[](sponsorInfo[_gameId].totalSponsors);
                SponsorInfo memory _sponsorInfo = sponsorInfo[_gameId];
                for (uint256 i = 0; i < sponsorInfo[_gameId].totalSponsors; i++) {
                    uint256 _sidePrizeFee = _sponsorInfo.amounts[i] * _feePercent / ONE_HUNDRED_PERCENT;
                    _sizePrizeAmounts[i] = (_sponsorInfo.amounts[i] - _sidePrizeFee) / _winners.length;
                    _transferSystemFee(_sponsorInfo.tokens[i], _sidePrizeFee, _gameInfo.creator);
                    IERC20(_sponsorInfo.tokens[i]).safeTransfer(address(prizeManager), _sponsorInfo.amounts[i] - _sidePrizeFee);
                }
                prizeManager.createSidePrize(_gameId, _sponsorInfo.tokens, _sizePrizeAmounts);
            }
        }
    }

    function _transferSystemFee(address _token, uint256 _amount, address _creator) internal {
        uint256 _creatorFee = _amount * creatorFeeRatio / BASE_RATIO;
        uint256 _operationFee = _amount - _creatorFee;
        IERC20(_token).safeTransfer(_creator, _creatorFee);
        IERC20(_token).safeTransfer(gamePolicy.getTreasuryAddress(), _operationFee);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    // 1 : down | 2 : up
    // startTime = 0 -> default
    
    function record(uint256 _gameId, uint256 _roundId, uint256  _players, uint256 _predictions) external onlyOperator {
        GameInfo storage _gameInfo = gameInfo[_gameId];
        require(_gameInfo.status != GAME_STATUS.CLOSED && _gameInfo.status != GAME_STATUS.CANCELED, "PredictionV5: closed");
        require(block.timestamp >= _gameInfo.startTime, "PredictionV5: !started");
        require(!isHasData[_gameId][_roundId], "PredictionV5: have data");

        if (_gameInfo.status == GAME_STATUS.PENDING) {
            _gameInfo.status = GAME_STATUS.AVAILABLE;
        }

        isHasData[_gameId][_roundId] = true;

        uint256 _previousRoundId = _gameInfo.currentRoundNumber;
        uint256 _startTime = _previousRoundId > 0 ? roundInfo[_gameId][_previousRoundId].startTime + ROUND_DURATION : gameInfo[_gameId].startTime;
         if (_gameInfo.nPlayers >= _gameInfo.minPlayers){
            RoundInfo memory _roundInfo = RoundInfo(
            _startTime,
            ROUND_RESULT.UNDEFINED,
            _players,
            _predictions,
            block.timestamp
        );
            roundInfo[_gameId][_roundId] = _roundInfo;
            _gameInfo.currentRoundNumber++;
        } else {
            // not start
            _finishGame(_gameId, _gameInfo.players, 1);
        }
        
        
    }
    
    function update(uint256 _gameId, uint256 _roundId, uint256 _result) external onlyOperator {
        require(roundInfo[_gameId][_roundId].result == ROUND_RESULT(0), "PredictionV5: have result");
        roundInfo[_gameId][_roundId].result = ROUND_RESULT(_result);
    }

    // 0 : normal | 1 : force finish with specific round
    function finish(uint256 _gameId, address[] memory _winners, bool _isConsoled) external onlyOperator {
        _finishGame(_gameId, _winners, _isConsoled? 3:2);
    }

    function changeSponsoredGameId(uint256 _oldGameId, uint256 _newGameId) external onlyOperator {
        require(gameInfo[_oldGameId].status == GAME_STATUS.CANCELED, "PredictionV5: !canceled");
        sponsorInfo[_newGameId] = sponsorInfo[_oldGameId];
        sponsorInfo[_oldGameId].totalSponsors = 0;
        emit SponsorChanged(_oldGameId, _newGameId, msg.sender);
    }


    function setWinningFee(uint256 _fee) external onlyOwner {
        require(_fee < ONE_HUNDRED_PERCENT, "PredictionV5: !fee");
        winingFeePercent = _fee;
    }

    function setCreationFee(address _token, uint256 _feeAmount) external onlyOwner {
        require(_feeAmount >= minCreationFeeAmount, "PredictionV5: !minCreationFee");
        creationFeeToken = _token;
        creationFeeAmount = _feeAmount;
    }

    function setConsolationPercent(uint256 _newPercent) external onlyOwner {
        consolationPercent = _newPercent;
    }

    function setSystemFeeRatio(uint256 _creatorRatio, uint256 _operationRatio) external onlyOwner {
        require(_creatorRatio + _operationRatio == BASE_RATIO, "PredictionV5: !data");
        creatorFeeRatio = _creatorRatio;
        operationFeeRatio = _operationRatio;
    }

    function setMinBuyIn(address[] memory _tokens, uint256[] memory _amounts) external onlyOwner {
        for (uint256 i = 0; i < _tokens.length; i++) {
            minBuyIn[_tokens[i]] = _amounts[i];
        }
    }

    function setMinCreationFee( uint256 _minFeeAmount) external onlyOwner {
        minCreationFeeAmount = _minFeeAmount;
    }



    // EVENTS
    event NewGameCreated(uint256 gameId);
    event GameFinished(uint256 gameId);
    event Sponsored(uint256 gameId, address token, uint256 amount, address sponsor);
    event SponsorChanged(uint256 oldGameId, uint256 newGameId, address operator);
    event NewPlayer(uint256 gameId, address player, uint256 index);
}
