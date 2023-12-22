// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./IERC20.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Math.sol";

import "./IFees.sol";
import "./IFeeder.sol";
import "./WardedUpgradeable.sol";
import "./console.sol";

contract QHFees is Initializable, UUPSUpgradeable, OwnableUpgradeable, WardedUpgradeable, IFees {

    mapping (uint256 => FundFees) public funds; // fundId => fees
    mapping (uint256 => FundFees) public gatheredFees;
    mapping (uint256 => uint256) public fundBalance;

    uint256 public gatheredServiceFees;

    uint256 public serviceSf;
    uint256 public servicePf;
    uint256 public serviceMf;

    IFeeder feeder;

    function initialize() public initializer {
        __Ownable_init();
        __Warded_init();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function setFeeder(IFeeder _feeder) external auth {
        feeder = _feeder;
    }

    function setServiceFees(uint256 sf, uint256 pf, uint256 mf) external auth {
        serviceSf = sf;
        servicePf = pf;
        serviceMf = mf;

        emit ServiceFeesChanged(serviceSf, servicePf, serviceMf);
    }

    function newFund(uint256 fundId, uint256 sf, uint256 pf, uint256 mf) external override auth {
        require(funds[fundId].live == 0, "Fees/fund-exists");

        funds[fundId] = FundFees({
            live: 1,
            sf: sf,
            pf: pf,
            mf: mf
        });

        emit NewFund(fundId, sf, pf, mf);
    }

    function fees(uint256 fundId) external override view returns(uint256 sf, uint256 pf, uint256 mf) {
        require(funds[fundId].live == 1, "Fees/fund-not-exists");

        return (funds[fundId].sf, funds[fundId].pf, funds[fundId].mf);
    }

    function serviceFees() external override view returns(uint256 sf, uint256 pf, uint256 mf) {
        return (serviceSf, servicePf, serviceMf);
    }

    // Must be called from the feeder
    function gatherSf(uint256 fundId, uint256 pending, address token) external override auth returns(uint256) {
        require(funds[fundId].live == 1, "Fees/fund-not-exists");

        uint256 totalSf = (funds[fundId].sf + serviceSf) * pending / 1e18;
        uint256 serviceShare = serviceSf * pending / 1e18;
        uint256 fundShare = totalSf - serviceShare;
        gatheredServiceFees += serviceShare;
        FundFees storage gatheredFees = gatheredFees[fundId];
        gatheredFees.sf += fundShare;
        fundBalance[fundId] += fundShare;

        IERC20(token).transferFrom(msg.sender, address(this), totalSf);

        emit SfCharged(fundId, totalSf);

        return pending - totalSf;
    }

    // Must be called from the trader
    function gatherPf(uint256 fundId, uint256 pending, address token) external override auth {
        require(funds[fundId].live == 1, "Fees/fund-not-exists");

        uint256 totalPf = this.calculatePF(fundId, pending);
        uint256 serviceShare = servicePf * pending / 1e18;
        uint256 fundShare = totalPf - serviceShare;
        gatheredServiceFees += serviceShare;
        FundFees storage gatheredFees = gatheredFees[fundId];
        gatheredFees.pf += fundShare;
        fundBalance[fundId] += fundShare;

        IERC20(token).transferFrom(msg.sender, address(this), totalPf);
        emit PfCharged(fundId, totalPf);
    }

    // Must be called from the trader
    function gatherMf(uint256 fundId, uint256 pending, address token, address manager) external override auth {
        require(funds[fundId].live == 1, "Fees/fund-not-exists");

        uint256 mf = (funds[fundId].mf + serviceMf) * pending / 1e18;
        FundFees storage gatheredFees = gatheredFees[fundId];
        gatheredFees.mf += mf;

        IERC20(token).transferFrom(msg.sender, manager, mf);

        emit MfCharged(fundId, mf);
    }

    function withdraw(address user, uint256 amount) external auth {
        require(gatheredServiceFees >= amount, "Fees/amount-exceeds-gathered-fees-amount");
        gatheredServiceFees -= amount;
        IERC20(feeder.getInvestToken()).transfer(user, amount);
        emit Withdrawal(user, feeder.getInvestToken(), amount);
    }

    function withdrawFund(uint256 fundId, address destination, uint256 amount) external {
        require(feeder.managers(fundId) == msg.sender, "Fees/sender-is-not-a-manager");
        require(fundBalance[fundId] >= amount, "Fees/amount-exceeds-gathered-fees-amount");
        fundBalance[fundId] -= amount;
        IERC20(feeder.getInvestToken()).transfer(destination, amount);
        emit WithdrawalFund(fundId, destination, feeder.getInvestToken(), amount);
    }

    function calculatePF(uint256 fundId, uint256 amount) external override view returns (uint256) {
        return (funds[fundId].pf + servicePf) * amount / 1e18;
    }
}

