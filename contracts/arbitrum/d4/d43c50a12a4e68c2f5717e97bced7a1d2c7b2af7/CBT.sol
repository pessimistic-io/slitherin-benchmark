pragma solidity ^0.8.17;

// from https://github.com/lsaether/bonding-curves

import {Bread} from "./Bread.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";

import "./BancorFormula.sol";

contract CBT is BancorFormula {
    event CurvedBuy(address indexed sender, uint256 amount, uint256 deposit);
    event CurvedSell(address indexed sender, uint256 amount, uint256 reimbursement);

    Bread public bread;
    uint256 public poolBalance;
    uint256 public reserveRatio;

    bool public live;

    constructor(uint256 _reserveRatio) {
        bread = Bread(msg.sender);
        reserveRatio = _reserveRatio;
    }

    function artificialSupply() internal view returns (uint256) {
        return bread.totalSupply() - bread.balanceOf(address(this));
    }

    function calculateCurvedMintReturn(uint256 _amount) public view returns (uint256 mintAmount) {
        return calculatePurchaseReturn(artificialSupply(), poolBalance, uint32(reserveRatio), _amount);
    }

    function calculateCurvedBurnReturn(uint256 _amount) public view returns (uint256 burnAmount) {
        return calculateSaleReturn(artificialSupply(), poolBalance, uint32(reserveRatio), _amount);
    }

    modifier onlyLive() {
        require(live, "CurveBondedToken: not live");
        _;
    }

    function buy() public payable onlyLive {
        _curvedBuy(msg.value);
    }

    // @param _amount scaled by 1e18
    function sell(uint256 _amount) public onlyLive {
        uint256 returnAmount = _curvedSell(_amount);
        SafeTransferLib.safeTransferETH(msg.sender, returnAmount);
    }

    function _curvedBuy(uint256 _deposit) internal returns (uint256) {
        uint256 amount = calculateCurvedMintReturn(_deposit);
        poolBalance += _deposit;
        bread.transfer(msg.sender, amount);
        emit CurvedBuy(msg.sender, amount, _deposit);
        return amount;
    }

    function _curvedSell(uint256 _amount) internal returns (uint256) {
        uint256 reimbursement = calculateCurvedBurnReturn(_amount);
        poolBalance -= reimbursement;
        bread.transferFrom(msg.sender, address(this), _amount);
        emit CurvedSell(msg.sender, _amount, reimbursement);
        return reimbursement;
    }

    function start() public payable {
        require(msg.sender == address(bread));
        live = true;
        poolBalance += msg.value;
    }
}

