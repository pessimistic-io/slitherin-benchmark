// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./GameUpgradeable.sol";

contract MegaDiceUpgradeable is
    GameUpgradeable
{
    uint256 public maxPos;
    uint256 public minPos;

    struct GameSession {
        address player;
        uint256 position;
        bool up;
        uint256 amount;
        uint256 reservedAmount;
        uint256 txIdentifier;
        uint256 sentValue;
        uint256 autoroolAmount;
    }
    mapping(bytes32 => GameSession) sessions;

    event GameSessionPlayed(
        address indexed user,
        uint256 sentValue,
        uint256 indexed txIdentifier,
        uint256 autoroolAmount,
        uint256 amount,
        bool up,
        uint256 position,
        uint256 payoutAmount,
        uint256[] randomValue
    );

    /** @dev Creates a contract.
    * @param _rootCaller Root caller of that contract.
    * @param _rng the callback contract
    */
    function initialize(
        address _rng,
        address _rootCaller,
        uint256 _minPos,
        uint256 _maxPos
    ) public payable initializer {
        require(
            _minPos >= 0 && _maxPos >= minPos && maxPos <= 10000,
            "_winnerCoefficient should be between 0 and 100"
        );
        GameUpgradeable.initialize_(
            _rng,
            _rootCaller
        );
        __Ownable_init();
        minPos = _minPos;
        maxPos = _maxPos;
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
        require(_data.length == uint256(2), "Not enough data. Expect 2 fields");
        bool _up = _data[0] % 2 == 1;
        uint256 _position = _data[1];
        require(
            _position <= maxPos && _position >= minPos,
            "Position out of allowed range"
        );
        
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
        uint256 _toReserve = calculateMaxPayoutAmmount(_value, _up, _position);
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
            position: _position,
            up: _up,
            reservedAmount: _toReserve,
            txIdentifier: _txIdentifier,
            sentValue: _value,
            autoroolAmount: _autoRollAmount
        });
    }

    /** @dev Shows available outcomes.
     * @param _up bool in the row.
     * @param _position uint256 in row.
     */
    function outcome(bool _up, uint256 _position)
        public
        pure
        returns (uint256)
    {
        if (_up) {
            return 10000 - _position;
        } else {
            return _position - 100;
        }
    }

    /** @dev Updates maxPosition and lowestPosition.
     * @param _inMax max position.
     * @param _inMin min position.
     */
    function setPos(uint256 _inMax, uint256 _inMin) public onlyOwner {
        maxPos = _inMax;
        minPos = _inMin;
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
                uint256 randomValue = randomWords[i] % 10000;
                if (
                    (!session.up && randomValue < session.position) ||
                    (session.up && randomValue > session.position)
                ) {
                    uint256 winning = (((session.amount / randomWords.length) *
                        10000) / outcome(session.up, session.position));
                    paidAmount += winning;
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
            session.up,
            session.position,
            paidAmount,
            randomWords
        );

        delete sessions[requestId];
    }

    function calculateMaxPayoutAmmount(
        uint256 _amount,
        bool _up,
        uint256 _position
    ) internal pure returns (uint256) {
        uint256 _winning;
        _winning = ((_amount * 10000) / (outcome(_up, _position)));
        return _winning;
    }
}

