// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.18;

import { ERC20 } from "./ERC20.sol";
import { IERC20 } from "./IERC20.sol";
import { IERC20Tax } from "./IERC20Tax.sol";
import { ERC20TaxReferenced } from "./ERC20TaxReferenced.sol";


contract FireDogeRacePool is ERC20TaxReferenced {

    struct Racer {
        address user;
        uint256 burnedAmount;
    }

    uint256 public lastEpoch;
    mapping(uint256 => mapping(address => uint256)) public racers;  // epoch => address => burnedAmount
    mapping(uint256 => Racer) public bestRacers;
    mapping(uint256 => uint256) public bestRacersDistributedAmount;

    IERC20 public immutable WETH;
    uint256 public immutable START_TIME;

    uint256 public constant DISTRIBUTION_DURATION = 45 minutes;
    uint256 public constant DISTRIBUTION_PART = 3;  // 1/3

    event WinnerAnnouncement(
        uint256 indexed epoch,
        address racer,
        uint256 burnedAmount,
        uint256 wethWon
    );

    event NewRacer(
        uint256 epoch,
        address racer,
        uint256 burnedAmount,
        bool isTheBest
    );

    constructor(IERC20 _weth) {
        WETH = _weth;
        START_TIME = block.timestamp;
    }

    function upsertRacer(
        address _racer,
        uint256 _burnedAmount
    ) external {
        require(msg.sender == address(TOKEN), "Racer can be injected only from swaps directly by token itself");

        uint256 _currentEpoch = (block.timestamp - START_TIME) / DISTRIBUTION_DURATION;
        racers[_currentEpoch][_racer] += _burnedAmount;

        Racer storage _bestRacer = bestRacers[_currentEpoch];

        emit NewRacer(
            _currentEpoch,
            _racer,
            _burnedAmount,
            _bestRacer.burnedAmount <= racers[_currentEpoch][_racer]
        );
        if (_bestRacer.burnedAmount <= racers[_currentEpoch][_racer]) {
            bestRacers[_currentEpoch] = Racer({
                user: _racer,
                burnedAmount: racers[_currentEpoch][_racer]
            });
        }

        // Previos epoch has been ended, rewards are going to winner!
        if (_currentEpoch != lastEpoch) {
            uint256 _distributionAmount = WETH.balanceOf(address(this)) / DISTRIBUTION_PART;
            if (_distributionAmount != 0) {
                WETH.transfer(
                    bestRacers[lastEpoch].user,
                    _distributionAmount
                );

                emit WinnerAnnouncement(
                    lastEpoch,
                    bestRacers[lastEpoch].user,
                    bestRacers[lastEpoch].burnedAmount,
                    _distributionAmount
                );
            }
            bestRacersDistributedAmount[lastEpoch] = _distributionAmount;
            lastEpoch = _currentEpoch;
        }
    }
}

