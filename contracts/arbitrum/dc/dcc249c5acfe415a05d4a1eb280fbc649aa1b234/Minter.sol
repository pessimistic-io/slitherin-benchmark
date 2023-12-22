// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import "./Initializable.sol";
import "./Math.sol";

import "./IMinter.sol";
import "./IRewardsDistributor.sol";
import "./IRam.sol";
import "./IVoter.sol";
import "./IVotingEscrow.sol";

// codifies the minting rules as per ve(3,3), abstracted from the token to support any token that allows minting

contract Minter is IMinter, Initializable {
    uint256 internal constant WEEK = 86400 * 7; // allows minting once per week (reset every Thursday 00:00 UTC)
    uint256 internal constant EMISSION = 990;
    uint256 internal constant TAIL_EMISSION = 2;
    uint256 internal constant PRECISION = 1000;
    uint256 internal constant TERMINAL_SUPPLY = 500_000_000 * 1e18;
    uint256 internal constant TERMINAL_REBASE = 200_000_000 * 1e18; //Supply from rebases
    uint256 internal constant TERMINAL_PARTNER_BOOST = 100_000_000 * 1e18; // Supply from 1m/week partner boost rebases
    uint256 internal constant TERMINAL_EMISSION = 1_000_000 * 1e18; // Emissions once terminal supply is hit
    uint256 internal constant MAX_GROWTH = 750; // 75%
    address public constant RAMSES_TIMELOCK =
        0x9314fC5633329d285F744108D637E1222CEbae1c;

    IRam public _ram;
    IVoter public _voter;
    IVotingEscrow public _ve;
    IRewardsDistributor public _rewards_distributor;
    address msig;

    uint256 public weekly;

    uint256 public active_period;
    uint256 public first_period;

    address public partnerRebaser;

    event SetVeDist(address _value);
    event SetVoter(address _value);
    event Mint(address indexed sender, uint256 weekly, uint256 growth);

    function initialize(
        address __voter, // the voting & distribution system
        address __ve, // the ve(3,3) system that will be locked into
        address __rewards_distributor, // the distribution system that ensures users aren't diluted
        uint256 initialSupply,
        address _msig
    ) external initializer {
        _ram = IRam(IVotingEscrow(__ve).token());
        _voter = IVoter(__voter);
        _ve = IVotingEscrow(__ve);
        _rewards_distributor = IRewardsDistributor(__rewards_distributor);

        emit SetVeDist(__rewards_distributor);
        emit SetVoter(__voter);

        if (initialSupply > 0) {
            _ram.mint(_msig, initialSupply);
        }

        weekly = 5_000_000 * 1e18; // represents a starting weekly emission of 15M RAM (RAM has 18 decimals)

        msig = _msig;
        active_period = type(uint256).max / 2;
    }

    // weekly emission takes the max of calculated (aka target) emission versus circulating tail end emission
    function weekly_emission() public view returns (uint256) {
        if (
            _ram.totalSupply() >=
            (TERMINAL_SUPPLY + TERMINAL_REBASE + TERMINAL_PARTNER_BOOST)
        ) {
            return TERMINAL_EMISSION;
        } else {
            return (weekly * EMISSION) / PRECISION;
        }
    }

    // calculate inflation and adjust ve balances accordingly
    function calculate_growth(uint256 _minted) public view returns (uint256) {
        uint256 rate = (active_period / WEEK - first_period / WEEK + 50) * 10;
        return (Math.min(rate, MAX_GROWTH) * _minted) / PRECISION;
    }

    function start_periods() external {
        require(msg.sender == msig, "!msig");
        require(first_period == 0, "Started");

        active_period = (block.timestamp / WEEK) * WEEK + WEEK;
        first_period = active_period;
        _ram.mint(msig, weekly);

        _rewards_distributor.checkpoint_token();
        _rewards_distributor.checkpoint_total_supply();

        emit Mint(msg.sender, weekly, 0);
    }

    // update period can only be called once per cycle (1 week)
    function update_period() external returns (uint256) {
        uint256 _period = active_period;
        if (block.timestamp >= _period + WEEK) {
            // only trigger if new week
            _period = (block.timestamp / WEEK) * WEEK;
            active_period = _period;
            weekly = weekly_emission();

            uint256 _growth = calculate_growth(weekly);
            uint256 _required = _growth + weekly;
            uint256 _balanceOf = _ram.balanceOf(address(this));
            if (_balanceOf < _required) {
                _ram.mint(address(this), _required - _balanceOf);
                if (weekly != TERMINAL_EMISSION) {
                    _ram.mint(partnerRebaser, (1_000_000 * 1e18));
                }
            }

            require(_ram.transfer(address(_rewards_distributor), _growth));
            _rewards_distributor.checkpoint_token(); // checkpoint token balance that was just minted in rewards distributor
            _rewards_distributor.checkpoint_total_supply(); // checkpoint supply

            _ram.approve(address(_voter), weekly);
            _voter.notifyRewardAmount(weekly);

            emit Mint(msg.sender, weekly, _growth);
        }
        return _period;
    }

    function updatePartnerRebaser(address _newPartnerRebaser) external {
        require(
            msg.sender == RAMSES_TIMELOCK,
            "Only the RAMSES timelock can call this function"
        );
        partnerRebaser = _newPartnerRebaser;
    }

    function getMisg() external view returns (address) {
        return msig;
    }
}

