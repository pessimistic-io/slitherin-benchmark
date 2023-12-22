// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./Game.sol";

contract GameRoulette is Game {
    error InvalidBet(uint256 bet);
    error InvalidData(uint256 _stake, uint256[50] _data);

    constructor (address _usdt, address _vault, address _console, address _house, address _rng, uint256 _id, uint256 _numbersPerRoll)
        Game(_usdt, _vault, _console, _house, _rng, _id, _numbersPerRoll)
    {}

    function finalize(uint256 _betId, uint256[] memory _randomNumbers) internal virtual override returns (uint256) {
        Types.Bet memory _bet = house.getBet(_betId);
        uint256[50] memory _bets = validateBet(_bet.betNum, _bet.data, _bet.stake);
        uint256[] memory _rolls = new uint256[](_bet.rolls);

        emit GameStart(_betId, _bet.betNum, _bets);

        uint256 _payout = 0;
        uint256 wins = 0;
        uint256 losses = 0;

        Types.Game memory ga = consoleInst.getGame(id);

        for (uint256 _i = 0; _i < _bet.rolls; _i++) {
            uint256 _roll = rng.getModulo(_randomNumbers[_i], 0, 36);
            if (_bets[_roll] != 0) {
                _payout += _bets[_roll] * (37 - ga.edge);
                wins ++;
            } else {
                losses ++;
            }

            _rolls[_i] = _roll;
        }

        emit GameEnd(_betId, _randomNumbers, _rolls, _bet.betNum, _bet.stake, wins, losses, _payout, _bet.player, block.timestamp);
        return _payout;
    }

    function validateBet(uint256 _bet, uint256[50] memory _data, uint256 _stake) public pure returns (uint256[50] memory) {
        if (_bet > 0) {
            revert InvalidBet(_bet);
        }
        uint256 _total;
        for (uint256 _i = 0; _i < 37; _i++) {
            _total += _data[_i];
        }
        if (_stake != _total || _total == 0) {
            revert InvalidData(_stake, _data);
        }
        return _data;
    }

    function getMaxPayout(uint256, uint256[50] memory _data) public virtual override view returns (uint256) {
        uint256 _largest = 0;
        uint256 _total = 0;

        for (uint256 _i = 0; _i < 37; _i++) {
            if (_data[_i] > _largest) {
                _largest = _data[_i];
            }
            _total += _data[_i];
        }

        if (_total == 0) {
            revert InvalidData(0, _data);
        }

        Types.Game memory ga = consoleInst.getGame(id);
        return (_largest * PAYOUT_AMPLIFIER) * ((37 - ga.edge) * PAYOUT_AMPLIFIER) / (_total * PAYOUT_AMPLIFIER);
    }
}

