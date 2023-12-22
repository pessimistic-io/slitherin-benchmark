// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.6;

import "./SafeMath.sol";
import "./IManager.sol";
import "./IERC20.sol";
import "./TransferHelper.sol";

contract RiskFunding {
    using SafeMath for uint256;

    address public manager;
    address public rewardAsset;
    uint256 public executeLiquidateFee;//fee to price provider by liquidator
    //liquidator => fee
    mapping(address => uint256)public liquidatorExecutedFees;

    event SetRewardAsset(address feeAsset);
    event SetExecuteLiquidateFee(uint256 _fee);
    event UseRiskFunding(address _token, address _to, uint256 _amount);
    event UpdateLiquidatorExecutedFee(address _liquidator, uint256 _executeLiquidateFee);
    event CollectExecutedFee(address _liquidator, uint256 _amount);

    constructor(address _manager) {
        require(_manager != address(0), "RiskFunding: invalid manager");
        manager = _manager;
    }

    modifier onlyController() {
        require(IManager(manager).checkController(msg.sender), "RiskFunding: Must be controller");
        _;
    }

    modifier onlyRouter(){
        require(IManager(manager).checkRouter(msg.sender), "RiskFunding: no permission!");
        _;
    }

    function setRewardAsset(address _rewardAsset) external onlyController {
        require(_rewardAsset != address(0), "RiskFunding: invalid reward asset");
        rewardAsset = _rewardAsset;
        emit SetRewardAsset(_rewardAsset);
    }

    function setExecuteLiquidateFee(uint256 _fee) external onlyController {
        executeLiquidateFee = _fee;
        emit SetExecuteLiquidateFee(_fee);
    }

    function updateLiquidatorExecutedFee(address _liquidator) external onlyRouter {
        liquidatorExecutedFees[_liquidator] = liquidatorExecutedFees[_liquidator].add(executeLiquidateFee);
        emit UpdateLiquidatorExecutedFee(_liquidator, executeLiquidateFee);
    }

    function useRiskFunding(address token, address to) external {
        require(IManager(manager).checkTreasurer(msg.sender), "RiskFunding: no permission!");
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "RiskFunding: no balance");
        TransferHelper.safeTransfer(token, to, balance);
        emit UseRiskFunding(token, to, balance);
    }

    function collectExecutedFee() external {
        require(liquidatorExecutedFees[msg.sender] > 0, "RiskFunding: no fee to collect");
        TransferHelper.safeTransfer(rewardAsset, msg.sender, liquidatorExecutedFees[msg.sender]);
        emit CollectExecutedFee(msg.sender, liquidatorExecutedFees[msg.sender]);
        liquidatorExecutedFees[msg.sender] = 0;
    }
}

