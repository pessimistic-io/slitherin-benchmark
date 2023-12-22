// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./GameUpgradeable.sol";

contract CoinFlipUpgradeable is GameUpgradeable {
    /*==================================================== Structs ==========================================================*/

    struct GameSession {
        address player;
        uint8 autoRollAmount;
        uint8 coinsTotal;
        uint8 coinsToWin;
        bool winningSide;
        uint256 gameId;
        address frontendReferral;
        uint256 startTime;
        address token;
        uint256 wager;
        uint256 reservedAmount;
        uint256 sentValue;
    }

    struct DecodedData {
        bool winningSide;
        uint8 coinsTotal;
        uint8 coinsToWin;
    }

    /*==================================================== State Variables ==========================================================*/

    mapping(bytes32 => GameSession) sessions;

    /*==================================================== Modifiers ==========================================================*/

    modifier isChoiceInsideLimits(bytes memory _gameData) {
        (
            bool winningSide_,
            uint8 coinsTotal_,
            uint8 coinsToWin_
        ) = _decodeGameData(_gameData);

        if (
            !(coinsTotal_ <= 10) ||
            !((coinsTotal_ < 6 && coinsToWin_ > 0) ||
                (coinsTotal_ < 9 && coinsToWin_ > 1) ||
                (coinsTotal_ >= 9 && coinsToWin_ > 2))
        ) {
            revert InvalidData();
        }
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
        address _gameProvider
    ) public payable initializer {
        __Game_init(_console, _rng, _vault, _gameProvider, "coinflip");
    }

    /** @dev Plays a game called.
     * @param _token one of whitelisted token contract address.
     * @param _frontendReferral frontend referral address
     * @param _autoRollAmount Amount of games in a call.
     * @param _sentAmount Amount that was initially sent.
     * @param _gameData Data that was sent for playing game. For that game expected [winningSide_, coinsTotal_, coinsToWin_], ex: [true, 2, 1]
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

    /*==================================================== Internal Functions ==========================================================*/

    /**  @notice decodes game data
     * @param _gameData encoded cohice. For that game expected [winningSide_, coinsTotal_, coinsToWin_], ex: [true, 2, 1]
     */
    function _decodeGameData(
        bytes memory _gameData
    )
        internal
        pure
        returns (bool winningSide_, uint8 coinsTotal_, uint8 coinsToWin_)
    {
        DecodedData memory gameDataDecoded_ = abi.decode(
            _gameData,
            (DecodedData)
        );

        (winningSide_, coinsTotal_, coinsToWin_) = (
            gameDataDecoded_.winningSide,
            gameDataDecoded_.coinsTotal,
            gameDataDecoded_.coinsToWin
        );
    }

    /** @dev Plays a game called.
     * @param _token one of whitelisted token contract address.
     * @param _frontendReferral frontend referral address
     * @param _autoRollAmount Amount of games in a call.
     * @param _sentAmount Amount that was initially sent.
     * @param _gameData Data that was sent for playing game. For that game expected [winningSide_, coinsTotal_, coinsToWin_], ex: [true, 2, 1]
     */
    function _create(
        address _token,
        address _frontendReferral,
        uint8 _autoRollAmount,
        uint256 _sentAmount,
        bytes memory _gameData
    ) internal isGameCountAcceptable(_autoRollAmount) incId {
        (
            bool winningSide_,
            uint8 coinsTotal_,
            uint8 coinsToWin_
        ) = _decodeGameData(_gameData);

        uint256 wager_ = (_sentAmount *
            (PERCENT_VALUE - vault.predictFees(id))) / PERCENT_VALUE;

        // calculate max possible payout, include also autoRoll
        uint256 toReserve_ = _calculateReward(wager_, coinsTotal_, coinsToWin_);

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
            coinsToWin: coinsToWin_,
            coinsTotal: coinsTotal_,
            winningSide: winningSide_,
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
                DecodedData({
                    winningSide: session_.winningSide,
                    coinsTotal: session_.coinsTotal,
                    coinsToWin: session_.coinsToWin
                })
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
            uint wonCoins_;

            uint256 randomValuePretty_;

            for (uint8 ii = 0; ii < _session.coinsTotal; ii++) {
                // (18439 % 10) / 1
                // (18439 % 100) / 10
                // (18439 % 1000) / 100
                // (18439 % 100) / 10
                // (18439 % 100) / 10

                // 1 = true; 0 = false
                bool randomValue_ = (((_randomWords[i] % (10 ** (ii + 1))) /
                    (10 ** (ii))) % 2) == 1;
                randomValuePretty_ += (randomValue_ ? 1 : 2) * (10 ** ii);
                if (randomValue_ == _session.winningSide) {
                    wonCoins_++;
                }
            }

            resultNumbers_[i] = randomValuePretty_;

            if ((wonCoins_ >= _session.coinsToWin)) {
                paidAmount_ +=
                    _calculateReward(
                        _session.wager,
                        _session.coinsTotal,
                        _session.coinsToWin
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
     * @param _coinsTotal total amount of coins
     * @param _coinsToWin amount of min winning coins
     */
    function _calculateReward(
        uint256 _amount,
        uint8 _coinsTotal,
        uint8 _coinsToWin
    ) internal view returns (uint256 _winning) {
        uint256 chanceMain;
        for (uint8 i = _coinsTotal; i >= _coinsToWin; i--) {
            uint256 c = (_factorial(_coinsTotal) * 1e18) /
                (_factorial(i) * _factorial(_coinsTotal - i));
            chanceMain += c;
        }
        _winning = (_amount * 1e18 * (2 ** _coinsTotal)) / chanceMain;
    }

    /** @dev calculates factorial, uses recursion
     * @param _n factorial number
     */
    function _factorial(uint8 _n) internal view returns (uint256) {
        return _n > 1 ? _n * _factorial(_n - 1) : 1;
    }
}

