// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Game.sol";

contract GameDice is Game {
    error InvalidBet(uint256 bet);

    constructor (address _usdt, address _vault, address _console, address _house, address _rng, uint256 _id, uint256 _numbersPerRoll)
        Game(_usdt, _vault, _console, _house, _rng, _id, _numbersPerRoll)
    {}
    
    function finalize(uint256 _betId, uint256[] memory _randomNumbers) internal virtual override returns (uint256) {
        Types.Bet memory _bet = house.getBet(_betId);
        uint256 _betNum = _bet.betNum;
        uint256 _payout;
        uint256[] memory _rolls = new uint256[](_bet.rolls);

        emit GameStart(_betId, _betNum, _bet.data);

        Types.Game memory ga = consoleInst.getGame(id);
        if (_betNum < ga.edge || _betNum + ga.edge > 100) {
            revert InvalidBet(_betNum);
        }

        uint256 payoutRatio = getMaxPayout(_betNum, _bet.data);
        uint256 wins = 0;
        uint256 losses = 0;

        for (uint256 _i = 0; _i < _bet.rolls; _i++) {
            uint256 _roll = rng.getModulo(_randomNumbers[_i], 0, 100);
            if(_roll > _betNum) {
                _payout += _bet.stake * payoutRatio / PAYOUT_AMPLIFIER;
                wins ++;
            } else {
                losses ++;
            }
            _rolls[_i] = _roll;
        }
        
        emit GameEnd(_betId, _randomNumbers, _rolls, _betNum, _bet.stake, wins, losses, _payout, _bet.player, block.timestamp);

        return _payout;
    }

    function getMaxPayout(uint256 _bet, uint256[50] memory) public virtual override view returns (uint256) {
        Types.Game memory ga = consoleInst.getGame(id);
        return ((100 - ga.edge) * PAYOUT_AMPLIFIER) / (100 - _bet);
    }
}

