// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./GameUpgradeable.sol";

contract MegaDiceUpgradeable is GameUpgradeable {
    /*==================================================== Structs ==========================================================*/

    struct GameSession {
        address player;
        uint16 position;
        uint8 autoRollAmount;
        bool up;
        uint256 gameId;
        address frontendReferral;
        uint256 startTime;
        address token;
        uint256 wager;
        uint256 reservedAmount;
        uint256 sentValue;
    }

    struct DecodedData {
        bool up;
        uint16 position;
    }

    /*==================================================== State Variables ==========================================================*/

    mapping(bytes32 => GameSession) sessions;
    uint16 public maxPos;
    uint16 public minPos;

    /*==================================================== Modifiers ==========================================================*/

    modifier isChoiceInsideLimits(bytes memory _gameData) {
        (, uint16 position_) = _decodeGameData(_gameData);

        if (!(position_ <= maxPos && position_ >= minPos)) {
            revert InvalidData();
        }
        _;
    }

    modifier checkPosition(uint16 _minPos, uint16 _maxPos) {
        require(
            _minPos >= 0 && _maxPos >= _minPos && _maxPos <= 10000,
            "MG: Positions should be between 0 and 10000"
        );
        _;
    }

    modifier isGameCreated(bytes32 _requestId) {
        require(
            sessions[_requestId].player != address(0),
            "Game is not created"
        );
        _;
    }

    /*==================================================== Functions ==========================================================*/

    /** @dev Creates a contract.
     * @param _console console contract address
     * @param _rng the callback contract
     * @param _vault the vault contract
     * @param _gameProvider the game provider royalty address
     * @param _minPos min position of the game
     * @param _maxPos max position of the game
     */
    function initialize(
        address _console,
        address _rng,
        address _vault,
        address _gameProvider,
        uint16 _minPos,
        uint16 _maxPos
    ) public payable initializer checkPosition(_minPos, _maxPos) {
        __Game_init(_console, _rng, _vault, _gameProvider, "megadice");
        minPos = _minPos;
        maxPos = _maxPos;
    }

    /** @dev Plays a game called.
     * @param _token one of whitelisted token contract address.
     * @param _frontendReferral frontend referral address
     * @param _autoRollAmount Amount of games in a call.
     * @param _sentAmount Amount that was initially sent.
     * @param _gameData Data that was sent for playing game. For that game expected [up_, position_], ex: [true, 1200]
     */
    function play(
        address _token,
        address _frontendReferral,
        uint8 _autoRollAmount,
        uint256 _sentAmount,
        bytes memory _gameData
    )
        external
        payable
        override
        nonReentrant
        whenNotPaused
        isChoiceInsideLimits(_gameData)
        checkGasPerRoll
    {
        _create(
            _token,
            _frontendReferral,
            _autoRollAmount,
            _sentAmount,
            _gameData
        );
    }

    /** @dev function to refund uncompleted game wagers
     * @param _requestId *
     */
    function refundGame(
        bytes32 _requestId
    )
        external
        override
        nonReentrant
        whenNotPaused
        whenNotCompleted(_requestId)
    {
        GameSession memory session_ = sessions[_requestId];

        if (session_.player != _msgSender()) {
            revert NotPlayer(_msgSender());
        }
        if (session_.startTime + refundCooldown >= block.timestamp) {
            revert NotRefundableYet();
        }

        _refundGame(_requestId);
    }

    /** @dev Fulfilling game, can be called only by RNG
     * @param _requestId *
     * @param _randomWords *
     */
    function fulfill(
        bytes32 _requestId,
        uint256[] memory _randomWords
    )
        external
        override
        onlyRNG
        isGameCreated(_requestId)
        whenNotCompleted(_requestId)
    {
        _fulfill(_requestId, _randomWords);
    }

    /** @dev Updates maxPosition and lowestPosition.
     * @param _minPos min position.
     * @param _maxPos max position.
     */
    function setPos(
        uint16 _minPos,
        uint16 _maxPos
    ) public checkPosition(_minPos, _maxPos) onlyGovernance {
        minPos = _minPos;
        maxPos = _maxPos;
    }

    /*==================================================== View Functions ==========================================================*/

    /** @dev Shows available outcomes.
     * @param _up bool in the row.
     * @param _position uint256 in row.
     */
    function outcome(bool _up, uint16 _position) public pure returns (uint16) {
        if (_up) {
            return 10000 - _position;
        } else {
            return _position - 100;
        }
    }

    /*==================================================== Internal Functions ==========================================================*/

    /**  @notice decodes game data
     * @param _gameData encoded choice. For that game expected [up_, position_], ex: [true, 1200]
     */
    function _decodeGameData(
        bytes memory _gameData
    ) internal pure returns (bool up_, uint16 position_) {
        DecodedData memory gameDataDecoded_ = abi.decode(
            _gameData,
            (DecodedData)
        );
        (up_, position_) = (gameDataDecoded_.up, gameDataDecoded_.position);
    }

    /** @dev Plays a game called.
     * @param _token one of whitelisted token contract address.
     * @param _frontendReferral frontend referral address
     * @param _autoRollAmount Amount of games in a call.
     * @param _sentAmount Amount that was initially sent.
     * @param _gameData Data that was sent for playing game. For that game expected [up_, position_], ex: [true, 1200]
     */
    function _create(
        address _token,
        address _frontendReferral,
        uint8 _autoRollAmount,
        uint256 _sentAmount,
        bytes memory _gameData
    ) internal isGameCountAcceptable(_autoRollAmount) incId {
        (bool up_, uint16 position_) = _decodeGameData(_gameData);

        uint256 wager_ = (_sentAmount *
            (PERCENT_VALUE - vault.predictFees(id))) / PERCENT_VALUE;

        // calculate max possible payout, include also autoRoll
        uint256 toReserve_ = _calculateReward(wager_, up_, position_);

        bytes32 requestId_ = _createBasic(
            _token,
            _autoRollAmount,
            toReserve_,
            _sentAmount
        );

        sessions[requestId_] = GameSession({
            player: _msgSender(),
            gameId: id,
            frontendReferral: _frontendReferral,
            startTime: block.timestamp,
            wager: wager_,
            token: _token,
            position: position_,
            up: up_,
            reservedAmount: toReserve_,
            sentValue: _sentAmount,
            autoRollAmount: _autoRollAmount
        });

        emit GameSessionCreated(requestId_);
    }

    /** @dev Fulfilling game, can be called only by RNG
     * @param _requestId *
     * @param _randomWords *
     */
    function _fulfill(
        bytes32 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        GameSession memory session_ = sessions[_requestId];

        (uint256[] memory resultNumbers_, uint256 paidAmount_) = _calculateGame(
            session_,
            _randomWords
        );

        emit GameSessionPlayed(
            session_.player,
            session_.gameId,
            gameName,
            session_.frontendReferral,
            session_.startTime,
            session_.wager,
            session_.token,
            paidAmount_,
            session_.sentValue,
            session_.autoRollAmount,
            abi.encode(
                DecodedData({up: session_.up, position: session_.position})
            ),
            resultNumbers_
        );
    }

    /** @dev Calculates gameData
     * @param _session *
     * @param _randomWords *
     */
    function _calculateGame(
        GameSession memory _session,
        uint256[] memory _randomWords
    ) internal returns (uint256[] memory resultNumbers_, uint256 paidAmount_) {
        resultNumbers_ = new uint256[](_randomWords.length);

        vault.addFees(
            _session.token,
            _session.frontendReferral,
            gameProvider,
            _session.sentValue,
            _session.gameId
        );

        for (uint8 i = 0; i < _randomWords.length; i++) {
            uint256 randomValue_ = _randomWords[i] % 10000;
            resultNumbers_[i] = randomValue_;
            if (
                (!_session.up && randomValue_ < _session.position) ||
                (_session.up && randomValue_ > _session.position)
            ) {
                paidAmount_ +=
                    _calculateReward(
                        _session.wager,
                        _session.up,
                        _session.position
                    ) /
                    _randomWords.length;
            }
        }
        vault.withdrawReservedAmount(
            _session.token,
            paidAmount_,
            _session.reservedAmount,
            _session.player
        );
    }

    /** @dev function to refund uncompleted game wagers
     * @param _requestId *
     */
    function _refundGame(bytes32 _requestId) internal {
        GameSession memory session_ = sessions[_requestId];

        vault.refund(
            session_.token,
            session_.sentValue,
            session_.reservedAmount,
            session_.player,
            session_.gameId
        );
        delete sessions[_requestId];
    }

    /** @dev calculate max possible payout
     * @param _amount amount of wager
     * @param _up whether up or down direction
     * @param _position position to be called
     */
    function _calculateReward(
        uint256 _amount,
        bool _up,
        uint16 _position
    ) internal pure returns (uint256) {
        return (_amount * 10000) / (outcome(_up, _position));
    }
}

