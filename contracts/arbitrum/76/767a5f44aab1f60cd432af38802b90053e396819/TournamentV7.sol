// --no verify
// support voucher
// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;
pragma experimental ABIEncoderV2;

import "./ReentrancyGuard.sol";
import "./SafeERC20.sol";
import "./ECDSA.sol";
import "./Ownable.sol";
import "./ERC20_IERC20.sol";
import "./IGamePolicy.sol";
import "./IPrizeManagerV3.sol";
import "./ITournamentV7.sol";
import "./IJackpot.sol";
import "./IVoucher.sol";
import "./IWarehouse.sol";

contract TournamentV7 is ReentrancyGuard, ITournamentV7, Ownable {
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
        uint256[] vouchers;
        GAME_STATUS status;
        address creator;
        uint256 totalVoucherAmount;
        address voucherPayer;
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

    struct WaitingRoom {
        address targetToken;
        address buyInToken;
        address[] players;
        uint256 nPlayers;
        uint256 buyInAmount;
        uint256 totalVoucherAmount;
        uint256[] vouchers;
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
    // address => gameId => voucherId
    mapping(address => mapping (uint256 => uint256)) public vouchers;
    // quick match target token => buy in token => buy in amount => waitingRoom
    mapping (address => mapping( address => mapping(uint256 => WaitingRoom))) public waitingRoom;
    // address => quick match target token => buy in token => buy in amount => bool
    mapping(address => mapping (address => mapping( address => mapping(uint256 => bool)))) public isJoinedWaitingRoom;
    // quick match target token => buy in token => buy in amount => id
    mapping (address => mapping( address => mapping(uint256 => uint256))) public rooms;


    IGamePolicy public gamePolicy;
    IPrizeManagerV3 public prizeManager;
    IVoucher public voucher;
    IWarehouse public warehouse;
    address public feeReceiver;
    uint256 public currentGameId;
    uint256 public winingFeePercent;
    uint256 public operationFeeRatio;
    uint256 public creatorFeeRatio;
    uint256 public consolationPercent;
    uint256 public maxCreationFeeAmount;
    uint256 public delayTime;
    uint256 public limitStart;
    uint256 public quickmatch_max_round;
    uint256 public quickmatch_max_winner;
    uint256 public quickmatch_min_players;
    uint256 public quickmatch_max_players;
    uint256 public quickmatch_time_delay;
    uint256 public constant MAX_PLAYERS = 100;
    uint256 public constant MIN_PLAYERS = 50;
    uint256 public constant MAX_ROUNDS = 20;
    uint256 public constant ROUND_DURATION = 60; // 60s
    uint256 public constant ONE_HUNDRED_PERCENT = 10000;
    uint256 public constant BASE_RATIO = 1000;

    /* ========== MODIFIERS ========== */

    modifier onlyOperator {
        require(gamePolicy.isOperator(msg.sender), "PredictionV7: !operator");
        _;
    }

    /* ========== CONSTRUCTOR ========== */

    constructor (IGamePolicy _gamePolicy, address _prizeManager, address _voucher, address _feeReceiver, uint256 _currentGameId, address _warehouse) {
        gamePolicy = _gamePolicy;
        prizeManager = IPrizeManagerV3(_prizeManager);
        voucher = IVoucher(_voucher);
        feeReceiver = _feeReceiver;
        currentGameId = _currentGameId;
        maxCreationFeeAmount = 5e6;
        delayTime = 30;
        limitStart = 1 days;
        quickmatch_max_round = 10;
        quickmatch_min_players = 4;
        quickmatch_max_winner = 1;
        quickmatch_time_delay = 0;
        quickmatch_max_players = 10;
        warehouse = IWarehouse(_warehouse);
    }

    /* ========== VIEWS ========== */

    function getParticipants(uint256 _gameId) external view returns (address[] memory _result){
        GameInfo memory _gameInfo = gameInfo[_gameId];
        _result = new address[](_gameInfo.players.length);
        for (uint256 i = 0; i < _gameInfo.players.length; i++) {
            _result[i] = _gameInfo.players[i];
        }
    }

    function getPlayersInWaitingRoon(address _targetToken, address _buyInToken, uint256 _buyInAmount) external view returns (address[] memory _result){
        WaitingRoom memory _waitingRoom = waitingRoom[_targetToken][_buyInToken][_buyInAmount];
        _result = new address[](_waitingRoom.players.length);
        for (uint256 i = 0; i < _waitingRoom.players.length; i++) {
            _result[i] = _waitingRoom.players[i];
        }
    }

    function getPredictionOfPlayer(uint256 _gameId, uint256 _roundId, address _player) external view returns(uint _status, uint _prediction){
        uint256 _players = roundInfo[_gameId][_roundId].players;
        uint256 _predictions = roundInfo[_gameId][_roundId].predictions;

        uint256 _index = 0;
        GameInfo memory _gameInfo = gameInfo[_gameId];
        for (uint256 index = 0; index < _gameInfo.players.length; index++) {
            if(_gameInfo.players[index] == _player){
                _index = index;
                break;
            }
        }

        bytes memory bStatus = _toBinary(_players);
        bytes memory bPredictions = _toBinary(_predictions);

        _status = bStatus[_index] == bytes1("1") ? 1 : 0;
        _prediction = bPredictions[_index] == bytes1("1") ? 1 : 0;

        return (_status, _prediction);
    }

    function getPlayersAlive(uint256 _gameId, uint256 _roundId) external view returns (address[] memory _result) {
        GameInfo memory _gameInfo = gameInfo[_gameId];
        _result = new address[](_gameInfo.players.length);
        if( _roundId == 1 ){
            _result = _gameInfo.players;
            return _result;
        } else {
            uint256 _players = roundInfo[_gameId][_roundId - 1].players;
            bytes memory bStatus = _toBinary(_players);
             uint256 count = 0;
             for (uint256 index = 0; index < bStatus.length; index++) {
                if( bStatus[index] == bytes1("1")){
                    _result[count++] = _gameInfo.players[index];
                }
             }
        }
    }




    /* ========== PUBLIC FUNCTIONS ========== */

    function create(
        uint256 _maxPlayers,
        uint256 _minPlayers,
        uint256 _maxRounds,
        address _targetToken,
        address _buyInToken,
        uint256 _buyInAmount,
        uint256 _startTime,
        address _voucherPayer
    ) external {
        _startTime = ((_startTime - 1) / 60 + 1) * 60;
        require(_startTime > block.timestamp, "PredictionV7: !startTime");
        require(gamePolicy.isTargetToken(_targetToken), "PredictionV7: !target token");
        require(gamePolicy.isBuyInToken(_buyInToken), "PredictionV7: !buyIn token");
        require( _buyInAmount >= gamePolicy.getBuyInLimit(_buyInToken), "PredictionV7: !minBuyIn");
        require(_startTime <= block.timestamp + limitStart, "PredictionV7: Too early");
        address[] memory _newPlayers;
        uint256[] memory _newVouchers;
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
            _newPlayers,
            _newVouchers,
            block.timestamp < _startTime ? GAME_STATUS.PENDING : GAME_STATUS.AVAILABLE,
            msg.sender,
            0,
            _voucherPayer
        );
        gameInfo[currentGameId] = _gameInfo;
        uint256 _creationFee = _buyInAmount >= maxCreationFeeAmount ? maxCreationFeeAmount : _buyInAmount;
        if ( _creationFee > 0) {
            IERC20(_buyInToken).safeTransferFrom(msg.sender, feeReceiver, _creationFee);
        }
        emit NewGameCreated(currentGameId);
    }

    function join(uint256 _gameId, uint256 _voucherId) external nonReentrant {
        GameInfo storage _gameInfo = gameInfo[_gameId];
        require(_gameInfo.status == GAME_STATUS.PENDING && _gameInfo.startTime > block.timestamp + delayTime, "PredictionV7: started");
        require(!isJoinedGame[msg.sender][_gameId], "PredictionV7: joined");
        require(_gameInfo.nPlayers < _gameInfo.maxPlayers, "PredictionV7: enough player");
        uint256 _buyInAmount = _gameInfo.buyInAmount;
        if (_voucherId > 0) {
            require(voucher.ownerOf(_voucherId) == msg.sender, "PredictionV7: !owner");
            (address _voucherToken, uint256 _voucherAmount) = voucher.info(_voucherId);
            require(_voucherToken == _gameInfo.buyInToken, "PredictionV7: voucher != buyIn Token");
            if (_voucherAmount > _buyInAmount) {
                _voucherAmount = _buyInAmount;
            }
            voucher.remove(_voucherId, msg.sender);
            _buyInAmount -= _voucherAmount;
            _gameInfo.totalVoucherAmount += _voucherAmount;
        }

        IERC20(_gameInfo.buyInToken).safeTransferFrom(msg.sender, address(this), _buyInAmount);
        isJoinedGame[msg.sender][_gameId] = true;
        uint256 _index = _gameInfo.nPlayers;
        _gameInfo.nPlayers++;
        _gameInfo.players.push(msg.sender);
        _gameInfo.vouchers.push(_voucherId);
        address _jackpot = gamePolicy.getJackpotAddress();
        if (_jackpot != address(0)) {
            IJackpot(_jackpot).newTicket(msg.sender);
        }
        emit NewPlayer(_gameId, msg.sender, _index);
    }

    function sponsor(uint256 _gameId, address _token, uint256 _amount) external {
        require(gameInfo[_gameId].status == GAME_STATUS.PENDING, "PredictionV7: game started");

        SponsorInfo storage _sponsorInfo = sponsorInfo[_gameId];
        uint256 _limit = gamePolicy.getSponsorLimit(_token);
        require(_limit > 0 && _amount >= _limit, "PredictionV7: !sponsor");
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        _sponsorInfo.tokens.push(_token);
        _sponsorInfo.amounts.push(_amount);
        _sponsorInfo.sponsors.push(msg.sender);
        _sponsorInfo.totalSponsors++;
        emit Sponsored(_gameId, _token, _amount, msg.sender);
    }

    function joinWaitingRoom(address _targetToken, address _buyInToken, uint256 _buyInAmount, uint256 _voucherId) external nonReentrant{
        WaitingRoom storage _waitingRoom = waitingRoom[_targetToken][_buyInToken][_buyInAmount];
        require(_waitingRoom.nPlayers < quickmatch_max_players, "PredictionV7: max players");
        require(!isJoinedWaitingRoom[msg.sender][_targetToken][_buyInToken][_buyInAmount], "PredictionV7: joined waitingRoom");
        if( _waitingRoom.buyInToken == address(0)){
            address[] memory _newPlayers;
            uint256[] memory _newVouchers;
            WaitingRoom memory _tmpWaitingRoom = WaitingRoom(_targetToken, _buyInToken, _newPlayers, 0, _buyInAmount, 0, _newVouchers); 
            waitingRoom[_targetToken][_buyInToken][_buyInAmount] = _tmpWaitingRoom;
        }
        isJoinedWaitingRoom[msg.sender][_targetToken][_buyInToken][_buyInAmount] = true;
        
        if( _voucherId > 0){
            require(voucher.ownerOf(_voucherId) == msg.sender, "PredictionV7: !owner");
            (address _voucherToken, uint256 _voucherAmount) = voucher.info(_voucherId);
            require(_voucherToken == _buyInToken, "PredictionV7: voucher != buyIn Token");
            if (_voucherAmount > _buyInAmount) {
                _voucherAmount = _buyInAmount;
            }
            voucher.remove(_voucherId, msg.sender);
            _buyInAmount -= _voucherAmount;
            _waitingRoom.totalVoucherAmount += _voucherAmount;
            
        }

        uint256 _currentRoomId = rooms[_targetToken][_buyInToken][_buyInAmount];

        emit NewWaiter(_targetToken, _buyInToken, _buyInAmount, msg.sender, _waitingRoom.nPlayers, _currentRoomId);  

        _waitingRoom.players.push(msg.sender);
        _waitingRoom.nPlayers++;
        _waitingRoom.vouchers.push(_voucherId);
        

        IERC20(_buyInToken).safeTransferFrom(msg.sender, address(this), _buyInAmount);
    }

    function start(address _targetToken, address _buyInToken, uint256 _buyInAmount, address _voucherPayer) external onlyOperator{
        WaitingRoom storage _waitingRoom = waitingRoom[_targetToken][_buyInToken][_buyInAmount];
        require( _waitingRoom.nPlayers >= quickmatch_min_players, "PredictionV7: !min players");
        uint256 _startTime = ((block.timestamp + quickmatch_time_delay - 1) / 60 + 1) * 60;
        currentGameId++;
        uint256[] memory _newVouchers;
        address[] memory _newPlayers;
        GameInfo memory _gameInfo = GameInfo (
            _waitingRoom.nPlayers,
            quickmatch_min_players,
            quickmatch_max_round,
            _targetToken,
            _buyInToken,
            _buyInAmount,
            0,
            _startTime,
            _waitingRoom.nPlayers,
            _waitingRoom.players,
            _waitingRoom.vouchers,
            GAME_STATUS.AVAILABLE,
            msg.sender,
            _waitingRoom.totalVoucherAmount,
            _voucherPayer
        );
        gameInfo[currentGameId] = _gameInfo;
        rooms[_targetToken][_buyInToken][_buyInAmount] = currentGameId;
        uint256 _currentRoomId = rooms[_targetToken][_buyInToken][_buyInAmount];
        emit NewQuickMatchCreated(currentGameId, _startTime, _currentRoomId);

        _resetWaitingRoom(_waitingRoom.players, _targetToken, _buyInToken, _buyInAmount); 
        _waitingRoom.nPlayers = 0;
        _waitingRoom.players = _newPlayers;
        _waitingRoom.vouchers = _newVouchers;
        _waitingRoom.totalVoucherAmount = 0;
        rooms[_targetToken][_buyInToken][_buyInAmount]++;

    }

    function leave(address _targetToken, address _buyInToken, uint256 _buyInAmount) external nonReentrant{
        require(isJoinedWaitingRoom[msg.sender][_targetToken][_buyInToken][_buyInAmount], "PredictionV7: !joined waitingRoom");
        WaitingRoom storage _waitingRoom = waitingRoom[_targetToken][_buyInToken][_buyInAmount];

        for (uint256 index = 0; index < _waitingRoom.players.length; index++) {
            if( _waitingRoom.players[index] == msg.sender){
                _waitingRoom.players[index]  = _waitingRoom.players[_waitingRoom.players.length - 1];
                uint256 _currentRoomId = rooms[_targetToken][_buyInToken][_buyInAmount];
                emit ChangeIndex(_waitingRoom.players[index], index, _currentRoomId);

                _waitingRoom.players.pop();
                _waitingRoom.nPlayers--;

          
                isJoinedWaitingRoom[msg.sender][_targetToken][_buyInToken][_buyInAmount] = false;  

                if ( _waitingRoom.vouchers[index] > 0){
                    (address _voucherToken, uint256 _voucherAmount) = voucher.info(_waitingRoom.vouchers[index]);
                    if (_voucherAmount > _buyInAmount) {
                        _voucherAmount = _buyInAmount;
                    }
                    _waitingRoom.totalVoucherAmount -= _voucherAmount;
                    warehouse.recover(address(voucher), _waitingRoom.vouchers[index]);
                    _buyInAmount -= _voucherAmount;
                }
                
                IERC20(_waitingRoom.buyInToken).safeTransfer( msg.sender, _buyInAmount);

                _waitingRoom.vouchers[index] = _waitingRoom.vouchers[_waitingRoom.vouchers.length - 1];
                _waitingRoom.vouchers.pop();

                emit LeaveRoom(_currentRoomId, msg.sender);
                
            }
        }

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
        require(_gameInfo.status == GAME_STATUS.AVAILABLE || _gameInfo.status == GAME_STATUS.PENDING, "PredictionV7: !available");
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
            IERC20(_gameInfo.buyInToken).safeTransfer(address(prizeManager), _totalBuyIn - _gameInfo.totalVoucherAmount);
            prizeManager.createPrize(_gameId, _winners, _gameInfo.vouchers, _gameInfo.buyInToken, _gameInfo.buyInAmount);
            prizeManager.claimAll(_gameId);
        }
        if (_option == 2 || _option == 3) {
            uint256[] memory _newVouchers = new uint256[](_winners.length);
            uint256 _feePercent = winingFeePercent;
            if (_option == 3) {
                _feePercent = ONE_HUNDRED_PERCENT - consolationPercent;
            }
            uint256 _fee = _totalBuyIn * _feePercent / ONE_HUNDRED_PERCENT;
            uint256 _prizeAmount = (_totalBuyIn - _fee) / _winners.length;
            // get voucher
            if(_gameInfo.voucherPayer != address(0)){
                IERC20(_gameInfo.buyInToken).safeTransferFrom(_gameInfo.voucherPayer, address(this), _gameInfo.totalVoucherAmount);
            }
            IERC20(_gameInfo.buyInToken).safeTransfer(address(prizeManager), _totalBuyIn - _fee);
            prizeManager.createPrize(_gameId, _winners, _newVouchers, _gameInfo.buyInToken, _prizeAmount);
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

    function _toBinary(uint256 _value) internal pure returns (bytes memory) {
        if (_value == 0) {
            return "0";
        }
        uint256 bitCount = 0;
        uint256 tempValue = _value;
        while (tempValue > 0) {
            tempValue = tempValue >> 1;
            bitCount++;
        }
        bytes memory result = new bytes(bitCount);
        while (bitCount > 0) {
            result[--bitCount] = ((_value & 1) == 1) ? bytes1("1") : bytes1("0");
            _value = _value >> 1;
        }
        return result;
    }

    function _resetWaitingRoom(address[] memory _players, address _targetToken, address _buyInToken, uint256 _buyInAmount) internal {
        for (uint256 index = 0; index < _players.length; index++) {
            isJoinedWaitingRoom[_players[index]][_targetToken][_buyInToken][_buyInAmount] = false;
        }
    }


    /* ========== RESTRICTED FUNCTIONS ========== */

    // 1 : down | 2 : up
    // startTime = 0 -> default
    
    function record(uint256 _gameId, uint256 _roundId, uint256  _players, uint256 _predictions) external onlyOperator {
        GameInfo storage _gameInfo = gameInfo[_gameId];
        require(_gameInfo.status != GAME_STATUS.CLOSED && _gameInfo.status != GAME_STATUS.CANCELED, "PredictionV7: closed");
        require(block.timestamp >= _gameInfo.startTime && _gameInfo.startTime > 0, "PredictionV7: !started");
        require(!isHasData[_gameId][_roundId], "PredictionV7: have data");

        if (_gameInfo.status == GAME_STATUS.PENDING) {
            _gameInfo.status = GAME_STATUS.AVAILABLE;
        }
        isHasData[_gameId][_roundId] = true;
        uint256 _previousRoundId = _gameInfo.currentRoundNumber;
        _gameInfo.currentRoundNumber++;
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
            emit Record(_gameId, _roundId, _players, _predictions);
        } else {
            // not start
            _finishGame(_gameId, _gameInfo.players, 1);
        }
    }
    
    function update(uint256 _gameId, uint256 _roundId, uint256 _result) external onlyOperator {
        require(roundInfo[_gameId][_roundId].result == ROUND_RESULT(0), "PredictionV7: have result");
        roundInfo[_gameId][_roundId].result = ROUND_RESULT(_result);
    }

    // 0 : normal | 1 : force finish with specific round
    function finish(uint256 _gameId, address[] memory _winners, bool _isConsoled) external onlyOperator {
        _finishGame(_gameId, _winners, _isConsoled? 3:2);
        emit GameFinished( _gameId, _winners);
    }

    function changeSponsoredGameId(uint256 _oldGameId, uint256 _newGameId) external onlyOperator {
        require(gameInfo[_oldGameId].status == GAME_STATUS.CANCELED, "PredictionV7: !canceled");
        sponsorInfo[_newGameId] = sponsorInfo[_oldGameId];
        sponsorInfo[_oldGameId].totalSponsors = 0;
        emit SponsorChanged(_oldGameId, _newGameId, msg.sender);
    }


    function setWinningFee(uint256 _fee) external onlyOwner {
        require(_fee < ONE_HUNDRED_PERCENT, "PredictionV7: !fee");
        uint256 _oldWinningFee = winingFeePercent;
        winingFeePercent = _fee;
        emit WinningFeeChanged(_fee, _oldWinningFee);
    }

    function setConsolationPercent(uint256 _newPercent) external onlyOwner {
        uint256 _oldPercent = consolationPercent;
        consolationPercent = _newPercent;
        emit ConsolationPercentChanged(_newPercent, _oldPercent);
    }

    function setSystemFeeRatio(uint256 _creatorRatio, uint256 _operationRatio) external onlyOwner {
        require(_creatorRatio + _operationRatio == BASE_RATIO, "PredictionV7: !data");
        creatorFeeRatio = _creatorRatio;
        operationFeeRatio = _operationRatio;
        emit SystemFeeChanged(_creatorRatio, _operationRatio);
    }

    function setMaxCreationFee( uint256 _maxFeeAmount) external onlyOwner {
        require(_maxFeeAmount > 0, "PredictionV7: !minFee");
        uint256 _oldFeeAmount = maxCreationFeeAmount;
        maxCreationFeeAmount = _maxFeeAmount;
        emit MaxCreationFeeChanged(_maxFeeAmount, _oldFeeAmount);
    }

    function setDelay( uint256 _delayTime) external onlyOwner {
        uint256 _oldDelayTime = delayTime;
        delayTime = _delayTime;
        emit DelayTimeChanged(_delayTime, _oldDelayTime);
    }

    function setlimitStart( uint256 _limitStart) external onlyOwner {
        uint256 _oldLimitStart = limitStart;
        limitStart = _limitStart;
        emit LimitStartChanged(_limitStart, _oldLimitStart);
    }

    function setMinPlayersQuickMatch( uint256 _minPlayers) external onlyOperator {
        uint256 _oldMinPlayer = quickmatch_min_players;
        quickmatch_min_players = _minPlayers;
        emit MinPlayerQuickMatchChanged(_minPlayers, _oldMinPlayer);
    }

    function setMaxPlayersQuickMatch( uint256 _maxPlayers) external onlyOperator {
        uint256 _oldMaxPlayer = quickmatch_max_players;
        quickmatch_max_players = _maxPlayers;
        emit MaxPlayerQuickMatchChanged(_maxPlayers, _oldMaxPlayer);
    }

    function setMaxRoundsQuickMatch( uint256 _maxRounds) external onlyOperator {
        uint256 _oldMaxRound = quickmatch_max_round;
        quickmatch_max_round = _maxRounds;
        emit MaxPlayerQuickMatchChanged(_maxRounds, _oldMaxRound);
    }

    function setMaxWinnersQuickMatch( uint256 _maxWinners) external onlyOperator {
        uint256 _oldMaxWinner = quickmatch_max_winner;
        quickmatch_max_winner = _maxWinners;
        emit MaxWinnerQuickMatchChanged(_maxWinners, _oldMaxWinner);
    }

    function setTimeDelayQuickMatch( uint256 _timeDelay) external onlyOperator {
        uint256 _oldTimeDelay = quickmatch_time_delay;
        quickmatch_time_delay = _timeDelay;
        emit TimeDelayQuickMatchChanged(_timeDelay, _oldTimeDelay);
    }



    // EVENTS
    event NewGameCreated(uint256 gameId);
    event NewQuickMatchCreated(uint256 gameId, uint256 startTime, uint256 roomId);
    event GameFinished(uint256 gameId, address[] winners);
    event Sponsored(uint256 gameId, address token, uint256 amount, address sponsor);
    event SponsorChanged(uint256 oldGameId, uint256 newGameId, address operator);
    event NewPlayer(uint256 gameId, address player, uint256 index);
    event NewWaiter(address targetToken, address buyInToken, uint256 buyInAmount, address player, uint256 index, uint256 roomId);
    event ChangeIndex(address player, uint256 index, uint256 roomId);
    event LeaveRoom(uint256 gameId, address player);
    event Record(uint256 gameId, uint256 roundId, uint256 players, uint256 prediction);
    event WinningFeeChanged(uint256 newFee, uint256 oldFee);
    event ConsolationPercentChanged(uint256 newPercent, uint256 oldPercent);
    event SystemFeeChanged(uint256 creatorRatio, uint256 operatorRatio);
    event MaxCreationFeeChanged(uint256 newCreationFee, uint256 oldCreationFee);
    event DelayTimeChanged(uint256 newDelayTime, uint256 oldDelayTime);
    event LimitStartChanged( uint256 newLimitStart, uint256 oldLimitStart);
    event MinPlayerQuickMatchChanged(uint256 newMinPlayer, uint256 oldMinPlayer);
    event MaxPlayerQuickMatchChanged(uint256 newMaxPlayer, uint256 oldMaxPlayer);
    event MaxRoundsQuickMatchChanged(uint256 newMaxRound, uint256 oldMaxRound);
    event MaxWinnerQuickMatchChanged(uint256 newMaxWinner, uint256 oldMaxWinner);
    event TimeDelayQuickMatchChanged(uint256 newTimeDelay, uint256 oldTimeDelay);
}
