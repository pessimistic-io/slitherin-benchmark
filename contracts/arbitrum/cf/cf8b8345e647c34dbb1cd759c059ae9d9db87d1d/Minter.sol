// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import "./math_Math.sol";
import "./IMinter.sol";
import "./IRewardsDistributor.sol";
import "./ISterling.sol";
import "./IVoter.sol";
import "./IVotingEscrow.sol";

// codifies the minting rules as per ve(3,3), abstracted from the token to support any token that allows minting

contract Minter is IMinter {
    uint internal constant WEEK = 86400 * 7; // allows minting once per week (reset every Thursday 00:00 UTC)
    uint internal emission = 990;
    uint internal numEpoch;
    uint internal constant TAIL_EMISSION = 2;
    uint internal constant PRECISION = 1000;
    ISterling public immutable _sterling;
    IVoter public immutable _voter;
    IVotingEscrow public immutable _ve;
    // IRewardsDistributor public immutable _rewards_distributor;
    uint public weekly = 25_000 * 1e18; // represents a starting weekly emission of 25K STERLING (STERLING has 18 decimals)
    uint public active_period;
    uint internal constant LOCK = 86400 * 7 * 8; // 8 weeks
    uint internal constant LOCK_PARTNER = 86400 * 7 * 208; // 208 weeks (4 years)

    address internal initializer;
    address public team;
    address public pendingTeam;
    uint public teamRate;
    uint public constant MAX_TEAM_RATE = 50; // 50 bps = 5%

    event Mint(address indexed sender, uint weekly, uint circulating_supply, uint circulating_emission);

    constructor(
        address __voter, // the voting & distribution system
        address __ve // the ve(3,3) system that will be locked into
        // address __rewards_distributor // the distribution system that ensures users aren't diluted
    ) {
        initializer = msg.sender;
        team = msg.sender;
        teamRate = 50; // 50 bps = 5%
        _sterling = ISterling(IVotingEscrow(__ve).token());
        _voter = IVoter(__voter);
        _ve = IVotingEscrow(__ve);
        // _rewards_distributor = IRewardsDistributor(__rewards_distributor);
        active_period = ((block.timestamp + (2 * WEEK)) / WEEK) * WEEK;
    }

    function initialize(
        address[] memory claimants,
        uint[] memory amounts,
        uint max // sum amounts / max = % ownership of top protocols, so if initial 20m is distributed, and target is 25% protocol ownership, then max - 4 x 20m = 80m
    ) external {
        require(initializer == msg.sender);
        _sterling.mint(address(this), max);
        _sterling.approve(address(_ve), type(uint).max);
        for (uint i = 0; i < claimants.length; i++) {
            _ve.create_lock_for_partner(amounts[i], LOCK_PARTNER, claimants[i]); // CREATES LOCK_PARTNER FOR PARTNER TOKENS
        }
        initializer = address(0);
        active_period = ((block.timestamp) / WEEK) * WEEK; // allow minter.update_period() to mint new emissions THIS Thursday
    }

    function setTeam(address _team) external {
        require(msg.sender == team, "not team");
        pendingTeam = _team;
    }

    function acceptTeam() external {
        require(msg.sender == pendingTeam, "not pending team");
        team = pendingTeam;
    }

    function setTeamRate(uint _teamRate) external {
        require(msg.sender == team, "not team");
        require(_teamRate <= MAX_TEAM_RATE, "rate too high");
        teamRate = _teamRate;
    }

    // calculate circulating supply as total token supply - locked supply
    function circulating_supply() public view returns (uint) {
        return _sterling.totalSupply() - _ve.totalSupply();
    }

    // emission calculation is 1% of available supply to mint adjusted by circulating / total supply
    function calculate_emission() public view returns (uint) {
        return (weekly * emission) / PRECISION;
    }

    // weekly emission takes the max of calculated (aka target) emission versus circulating tail end emission
    function weekly_emission() public view returns (uint) {
        return Math.max(calculate_emission(), circulating_emission());
    }

    // calculates tail end (infinity) emissions as 0.2% of total supply
    function circulating_emission() public view returns (uint) {
        return (circulating_supply() * TAIL_EMISSION) / PRECISION;
    }

    // REMOVE REBASE
    // calculate inflation and adjust ve balances accordingly
    // function calculate_growth(uint _minted) public view returns (uint) {
    //     uint _veTotal = _ve.totalSupply();
    //     uint _sterlingTotal = _sterling.totalSupply();
    //     return
    //         (((((_minted * _veTotal) / _sterlingTotal) * _veTotal) / _sterlingTotal) *
    //             _veTotal) /
    //         _sterlingTotal /
    //         2;
    // }

    // update period can only be called once per cycle (1 week)
    function update_period() external returns (uint) {
        uint _period = active_period;
        if (block.timestamp >= _period + WEEK && initializer == address(0)) { // only trigger if new week
            _period = (block.timestamp / WEEK) * WEEK;
            active_period = _period;
            weekly = weekly_emission();

            // REMOVE REBASE
            // uint _growth = calculate_growth(weekly);

            // uint _teamEmissions = (teamRate * (_growth + weekly)) /
            //     (PRECISION - teamRate);
            uint _teamEmissions = (teamRate * weekly) / PRECISION;
            uint _required = weekly + _teamEmissions;
            // uint _required = _growth + weekly + _teamEmissions;
            uint _balanceOf = _sterling.balanceOf(address(this));
            if (_balanceOf < _required) {
                _sterling.mint(address(this), _required - _balanceOf);
            }

            unchecked {
                ++numEpoch;
            }
            if (numEpoch == 208) emission = 999;

            require(_sterling.transfer(team, _teamEmissions));

            // REMOVE REBASE
            // require(_sterling.transfer(address(_rewards_distributor), _growth));
            // _rewards_distributor.checkpoint_token(); // checkpoint token balance that was just minted in rewards distributor
            // _rewards_distributor.checkpoint_total_supply(); // checkpoint supply

            _sterling.approve(address(_voter), weekly);
            _voter.notifyRewardAmount(weekly);

            emit Mint(msg.sender, weekly, circulating_supply(), circulating_emission());
        }
        return _period;
    }
}

