// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./GameUpgradeable.sol";

contract LimboUpgradeable is GameUpgradeable {
    /*==================================================== Structs ==========================================================*/

    struct GameSession {
        address player;
        uint8 autoRollAmount;
        uint32 target;
        uint256 gameId;
        address frontendReferral;
        uint256 startTime;
        address token;
        uint256 wager;
        uint256 gameFee;
        uint256 reservedAmount;
        uint256 sentValue;
    }

    struct DecodedData {
        uint32 target;
    }

    /*==================================================== State Variables ==========================================================*/

    mapping(bytes32 => GameSession) sessions;
    uint32 public minMultiplier;
    uint32 public maxMultiplier;

    /*==================================================== Modifiers ==========================================================*/

    modifier isChoiceInsideLimits(bytes memory _gameData) {
        uint32 target_ = _decodeGameData(_gameData);

        if (target_ < minMultiplier || target_ > maxMultiplier) {
            revert InvalidData();
        }
        _;
    }

    modifier checkPosition(uint32 _minMultiplier, uint32 _maxMultiplier) {
        require(
            _minMultiplier >= 100 &&
                _maxMultiplier >= _minMultiplier &&
                _maxMultiplier <= 100000000,
            "LIMBO: Positions should be between 100 and 100000000"
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
     */
    function initialize(
        address _console,
        address _rng,
        address _vault,
        address _gameProvider,
        uint32 _minMultiplier,
        uint32 _maxMultiplier
    ) public payable initializer checkPosition(_minMultiplier, _maxMultiplier) {
        __Game_init(_console, _rng, _vault, _gameProvider, "limbo");
        minMultiplier = _minMultiplier;
        maxMultiplier = _maxMultiplier;
    }

    /** @dev Plays a game called.
     * @param _token one of whitelisted token contract address.
     * @param _frontendReferral frontend referral address
     * @param _autoRollAmount Amount of games in a call.
     * @param _sentAmount Amount that was initially sent.
     * @param _gameData Data that was sent for playing game. For that game expected [target_], ex: [1000]
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
     * @param _minMultiplier min position.
     * @param _maxMultiplier max position.
     */
    function setPos(
        uint32 _minMultiplier,
        uint32 _maxMultiplier
    ) public checkPosition(_minMultiplier, _maxMultiplier) onlyGovernance {
        minMultiplier = _minMultiplier;
        maxMultiplier = _maxMultiplier;
    }

    /*==================================================== Internal Functions ==========================================================*/

    /**  @notice decodes game data
     * @param _gameData encoded cohice. For that game expected [target_], ex: [1000]
     */
    function _decodeGameData(
        bytes memory _gameData
    ) internal pure returns (uint32 target_) {
        DecodedData memory gameDataDecoded_ = abi.decode(
            _gameData,
            (DecodedData)
        );

        (target_) = (gameDataDecoded_.target);
    }

    /** @dev Plays a game called.
     * @param _token one of whitelisted token contract address.
     * @param _frontendReferral frontend referral address
     * @param _autoRollAmount Amount of games in a call.
     * @param _sentAmount Amount that was initially sent.
     * @param _gameData Data that was sent for playing gam. For that game expected [target_], ex: [1000]
     */
    function _create(
        address _token,
        address _frontendReferral,
        uint8 _autoRollAmount,
        uint256 _sentAmount,
        bytes memory _gameData
    ) internal isGameCountAcceptable(_autoRollAmount) incId {
        uint32 target_ = _decodeGameData(_gameData);

        uint256 gameFee_ = vault.predictFees(id);

        uint256 wager_ = (_sentAmount * (PERCENT_VALUE - gameFee_)) /
            PERCENT_VALUE;

        // calculate max possible payout, include also autoRoll
        uint256 toReserve_ = _calculateReward(wager_, target_);

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
            gameFee: gameFee_,
            token: _token,
            target: target_,
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
            abi.encode(DecodedData({target: session_.target})),
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

        uint32 baseMod_ = maxMultiplier - minMultiplier + 1;

        for (uint8 i = 0; i < _randomWords.length; i++) {
            uint256 H_ = _modNumber(_randomWords[i], baseMod_);
            uint256 multiplier_ = (((PERCENT_VALUE - _session.gameFee) *
                maxMultiplier *
                100) / (maxMultiplier - H_)) / PERCENT_VALUE;

            resultNumbers_[i] = multiplier_ >= minMultiplier ? multiplier_ : minMultiplier;

            if (_session.target <= multiplier_) {
                paidAmount_ +=
                    _calculateReward(_session.wager, _session.target) /
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
     * @param _target the made bet
     */
    function _calculateReward(
        uint256 _amount,
        uint32 _target
    ) internal pure returns (uint256) {
        return (_amount * _target) / 100;
    }

    /** @dev calculate mod number
     * @param _number *
     * @param _mod *
     */
    function _modNumber(
        uint256 _number,
        uint32 _mod
    ) internal pure returns (uint256 modded_) {
        unchecked {
            modded_ = _mod > 0 ? _number % _mod : _number;
        }
    }
}

