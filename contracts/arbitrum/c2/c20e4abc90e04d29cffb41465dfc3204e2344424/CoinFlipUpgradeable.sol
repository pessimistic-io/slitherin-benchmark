// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./GameUpgradeable.sol";

library Errors {
    error InvalidData();
}

contract CoinFlipUpgradeable is
    GameUpgradeable
{
    event GameSessionPlayed(
        address indexed user,
        uint256 sentValue,
        uint256 indexed txIdentifier,
        uint256 autoroolAmount,
        uint256 amount,
        bool winningSide,
        uint256 coinsTotal,
        uint256 coinsToWin,
        uint256 payoutAmount,
        uint256[] randomValue
    );

    struct GameSession {
        address player;
        uint256 coinsTotal;
        uint256 coinsToWin;
        bool winningSide;
        uint256 amount;
        uint256 reservedAmount;
        uint256 txIdentifier;
        uint256 sentValue;
        uint256 autoroolAmount;
    }

    mapping(bytes32 => GameSession) sessions;

    /** @dev Creates a contract.
    * @param _rootCaller Root caller of that contract.
    * @param _rng the callback contract
    */
    function initialize(
        address _rng,
        address _rootCaller
    ) public payable initializer {
        GameUpgradeable.initialize_(
            _rng,
            _rootCaller
        );
        __Ownable_init();
    }

    /** @dev Plays a game called.
     * @param _player Player wallet address.
     * @param _value Amount that was initially sent.
     * @param _txIdentifier Identificator for explorer scan.
     * @param _autoRollAmount Amount of games in a call.
     * @param _data Data that was sent for playing game. For that game expected [_up, _position], ex: [true, 1200]
     */
    function play(
        address _player,
        uint256 _value,
        uint256 _txIdentifier,
        uint256 _autoRollAmount,
        uint256[] memory _data
    ) public payable onlyOwnerOrRootCallerAccount {
        require(_data.length == uint256(3), "Not enough data. Expect 3 fields");
        bool _winningSide = _data[0] % 2 == 1;
        uint256 _coinsTotal = _data[1];
        uint256 _coinsToWin = _data[2];

        require(
            _coinsTotal <= 10,
            "CoinsTotal out of allowed range"
        );

        if (
            !((_coinsTotal < 6 && _coinsToWin > 0) ||
            (_coinsTotal < 9 && _coinsToWin > 1) ||
            (_coinsTotal >= 9 && _coinsToWin > 2))
            ) {
                revert Errors.InvalidData();
            }

        require(
            _autoRollAmount >= 1 && _autoRollAmount <= 100,
            "autoroll amount should be in [1...100]"
        );

        require(
            _value >= minBetAmount * _autoRollAmount && _value <= maxBetAmount * _autoRollAmount,
            "amount should be more than min and less than max"
        );

        MainStructs.ReservedAmount memory _reservedAmount;
        _reservedAmount = gamesPoolContract.reservedAmount(address(this));
        // Здесь нужно подсчитывать, какой по итогу максимальный пейаут может получиться
        uint256 _toReserve = calculateMaxPayoutAmmount(_value, _coinsTotal, _coinsToWin);
        require(
            _toReserve < maxPayout,
            "payout is higher than max possible"
        );
        require(
            _reservedAmount.amount + msg.value >=
                _reservedAmount.reserved + _toReserve,
            "not enough funds on contract"
        );
        gamesPoolContract.depositReservedAmount{value: msg.value}(_toReserve);

        bytes32 requestId = rng.makeRequestUint256Array(_autoRollAmount);

        sessions[requestId] = GameSession({
            player: _player,
            amount: msg.value,
            coinsToWin: _coinsToWin,
            coinsTotal: _coinsTotal,
            winningSide: _winningSide,
            reservedAmount: _toReserve,
            txIdentifier: _txIdentifier,
            sentValue: _value,
            autoroolAmount: _autoRollAmount
        });
    }

    function fulfill(bytes32 requestId, uint256[] memory randomWords)
        external
        onlyRNG
    {

        GameSession memory session = sessions[requestId];

        require(
            sessions[requestId].player != address(0),
            "Request ID not known"
        );
        
        uint256 paidAmount = 0;
        for (uint256 i = 0; i < randomWords.length; i++) {
            if (session.amount > 0) {
                uint wonCoins;
                for (uint256 ii = 0; ii < session.coinsTotal; ii++) {
                    // (18439 % 10) / 1
                    // (18439 % 100) / 10
                    // (18439 % 1000) / 100
                    // (18439 % 100) / 10
                    // (18439 % 100) / 10

                    // 1 = true; 0 = false
                    bool randomValue = (((randomWords[i] % (10 ** (ii + 1))) / (10 ** (ii))) % 2) == 1;
                    if (randomValue == session.winningSide) {
                        wonCoins++;
                    }
                }
                if (
                    (wonCoins >= session.coinsToWin)
                ) {
                    uint256 chanceMain;
                    for (uint256 ii = session.coinsTotal; ii >= session.coinsToWin; ii--) {
                        uint256 c =
                            factorial(session.coinsTotal) / (factorial(ii) * factorial(session.coinsTotal - ii));
                        chanceMain += c;
                    }
                    uint256 _winning = (session.amount / randomWords.length) * (2 ** session.coinsTotal) / chanceMain;
                    paidAmount += _winning;
                }
            }
        }
        bool success = gamesPoolContract.withdrawReservedAmount(
                paidAmount,
                session.reservedAmount,
                session.player
            );
        if (paidAmount != uint256(0) && !success) {
            emit GamePayoutFailed(
                session.player,
                paidAmount,
                session.txIdentifier
            );
        }
        emit GameSessionPlayed(
            session.player,
            session.sentValue,
            session.txIdentifier,
            session.autoroolAmount,
            session.amount,
            session.winningSide,
            session.coinsTotal,
            session.coinsToWin,
            paidAmount,
            randomWords
        );

        delete sessions[requestId];
    }

    function calculateMaxPayoutAmmount(
        uint256 _amount,
        uint256 _coinsTotal,
        uint256 _coinsToWin
    ) internal view returns (uint256) {
        uint256 _winning;
        uint256 chanceMain;
        for (uint256 i = _coinsTotal; i >= _coinsToWin; i--) {
            uint256 c =
                factorial(_coinsTotal) / (factorial(i) * factorial(_coinsTotal - i));
            chanceMain += c;
        }
        _winning = _amount * (2 ** _coinsTotal) / chanceMain;
        return _winning;
    }

    function factorial(uint256 _n) internal view returns (uint256) {
      return _n > 1 ? _n * factorial(_n - 1) : 1;
    }
}

