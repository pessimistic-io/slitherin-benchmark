// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./SafeERC20Upgradeable.sol";
import "./IERC20.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Math.sol";

import "./IFees.sol";
import "./IFeeder.sol";
import "./IRegistry.sol";
import "./Upgradeable.sol";

uint256 constant MAX_SF = 50000000000000000;
uint256 constant MAX_PF = 500000000000000000;

// @address:REGISTRY
IRegistry constant registry = IRegistry(0xe8258b0003CB159c75bfc2bC2D079d12E3774a80);

contract Fees is Initializable, Upgradeable, IFees {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeERC20Upgradeable for IERC20MetadataUpgradeable;

    mapping (uint256 => FundFees) public funds; // fundId => fees
    mapping (uint256 => FundFees) public gatheredFees;
    mapping (uint256 => uint256) public fundBalance;

    uint256 public gatheredServiceFees;

    uint256 public serviceSf;
    uint256 public servicePf;
    uint256 public serviceMf;

    modifier feederOnly() {
        require(msg.sender == address(registry.feeder()), "FE/AD"); // access denied
        _;
    }

    modifier factoryOnly() {
        require(msg.sender == address(registry.fundFactory()), "FE/AD"); // access denied
        _;
    }

    function initialize() public initializer {
        __Ownable_init();
    }

    function setServiceFees(uint256 sf, uint256 pf, uint256 mf) external onlyOwner {
        require(sf <= MAX_SF, "FE/IS"); // invalid sf
        require(pf <= MAX_PF, "FE/IP"); // invalid pf
        serviceSf = sf;
        servicePf = pf;
        serviceMf = mf;

        emit ServiceFeesChanged(serviceSf, servicePf, serviceMf);
    }

    function newFund(uint256 fundId, uint256 sf, uint256 pf, uint256 mf) external override factoryOnly {
        require(funds[fundId].live == 0, "FE/FE"); // fund exists
        require(sf <= MAX_SF, "FE/IS"); // invalid sf
        require(pf <= MAX_PF, "FE/IP"); // invalid pf

        funds[fundId] = FundFees({
            live: 1,
            sf: sf,
            pf: pf,
            mf: mf
        });

        emit NewFund(fundId, sf, pf, mf);
    }

    function fees(uint256 fundId) external override view returns(uint256 sf, uint256 pf, uint256 mf) {
        require(funds[fundId].live == 1, "FE/FNE"); // fund doesn't exist

        return (funds[fundId].sf, funds[fundId].pf, funds[fundId].mf);
    }

    function serviceFees() external override view returns(uint256 sf, uint256 pf, uint256 mf) {
        return (serviceSf, servicePf, serviceMf);
    }

    // Must be called from the feeder
    function gatherSf(uint256 fundId, uint256 pending, address token) external override feederOnly returns(uint256) {
        require(funds[fundId].live == 1, "FE/FNE");

        uint256 totalSf = (funds[fundId].sf + serviceSf) * pending / 1e18;
        uint256 serviceShare = serviceSf * pending / 1e18;
        uint256 fundShare = totalSf - serviceShare;
        gatheredServiceFees += serviceShare;
        FundFees storage fundFees = gatheredFees[fundId];
        fundFees.sf += fundShare;
        fundBalance[fundId] += fundShare;

        IERC20Upgradeable(token).safeTransferFrom(msg.sender, address(this), totalSf);

        emit SfCharged(fundId, totalSf);

        return pending - totalSf;
    }

    // Must be called from the feeder
    function gatherPf(uint256 fundId, uint256 pending, address token) external override feederOnly {
        require(funds[fundId].live == 1, "FE/FNE");

        uint256 totalPf = this.calculatePF(fundId, pending);
        uint256 serviceShare = servicePf * pending / 1e18;
        uint256 fundShare = totalPf - serviceShare;
        gatheredServiceFees += serviceShare;
        FundFees storage fundFees = gatheredFees[fundId];
        fundFees.pf += fundShare;
        fundBalance[fundId] += fundShare;

        IERC20Upgradeable(token).safeTransferFrom(msg.sender, address(this), totalPf);
        emit PfCharged(fundId, totalPf);
    }

    function gatherEf(uint256 fundId, uint256 amount, address token) external override {
        require(funds[fundId].live == 1, "FE/FNE");
        (address trade,,) = registry.interaction().fundInfo(fundId);
        require(msg.sender == address(registry.feeder()) || msg.sender == trade, "FE/AD");
        gatheredServiceFees += amount;
        IERC20Upgradeable(token).safeTransferFrom(msg.sender, address(this), amount);
        emit EfCharged(fundId, amount);
    }

    // create fund fee, we consider it as execution fee
    function gatherCf(uint256 fundId, address payer, uint256 amount, address token) external override factoryOnly {
        require(funds[fundId].live == 1, "FE/FNE");
        gatheredServiceFees += amount;
        IERC20Upgradeable(token).safeTransferFrom(payer, address(this), amount);
        emit EfCharged(fundId, amount);
    }

    function withdraw(address user, uint256 amount) external {
        require(msg.sender == address(registry.triggerServer()), "FE/SNTS"); // sender is not a trigger server
        require(gatheredServiceFees >= amount, "FE/AEB"); // amount exceeds balance
        gatheredServiceFees -= amount;
        registry.usdt().safeTransfer(user, amount);
        emit Withdrawal(user, address(registry.usdt()), amount);
    }

    function withdrawFund(uint256 fundId, address destination, uint256 amount) external {
        require(registry.feeder().managers(fundId) == msg.sender, "FE/SNM"); // sender not manager
        require(fundBalance[fundId] >= amount, "FE/AEB");
        fundBalance[fundId] -= amount;
        registry.usdt().safeTransfer(destination, amount);
        emit WithdrawalFund(fundId, destination, address(registry.usdt()), amount);
    }

    function calculatePF(uint256 fundId, uint256 amount) external override view returns (uint256) {
        return (funds[fundId].pf + servicePf) * amount / 1e18;
    }
}

