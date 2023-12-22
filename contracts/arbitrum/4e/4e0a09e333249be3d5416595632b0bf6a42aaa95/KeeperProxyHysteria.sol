// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import { Address } from "./Address.sol";
import { SafeMath } from "./SafeMath.sol";

/**
 * This interface is here for the keeper proxy to interact
 * with the strategy
 */
interface CoreStrategyAPI {
    function harvestTrigger(uint256 callCost) external view returns (bool);
    function harvest() external;
    function calcDebtRatio() external view returns (uint256);
    function debtLower() external view returns (uint256);
    function debtUpper() external view returns (uint256);
    function calcCollateral() external view returns (uint256);
    function collatLower() external view returns (uint256);
    function collatUpper() external view returns (uint256);
    function rebalanceDebt() external;
    function rebalanceCollateral() external;
    function strategist() external view returns (address);
    function vault() external view returns (address);
}

interface IVault {
    function strategies(address _strategy) external view returns(uint256 performanceFee, uint256 activation, uint256 debtRatio, uint256 minDebtPerHarvest, uint256 maxDebtPerHarvest, uint256 lastReport, uint256 totalDebt, uint256 totalGain, uint256 totalLoss);
}

/**
 * @title Robovault Keeper Proxy
 * @author robovault
 * @notice
 *  KeeperProxy implements a proxy for Robovaults CoreStrategy. The proxy provide
 *  More flexibility will roles, allowing for multiple addresses to be granted
 *  keeper permissions.
 *
 */
contract KeeperProxyHysteria {
    using Address for address;
    using SafeMath for uint256;

    CoreStrategyAPI public strategy;
    address public strategist;
    uint256 public hysteriaDebt = 10; // +/- 0.1%
    uint256 public hysteriaCollateral = 10; // +/- 0.1%
    mapping(address => bool) public keepers;
    address[] public keepersList;

    constructor(address _strategy) {
        setStrategyInternal(_strategy);
    }

    function _onlyStrategist() internal {
        require(msg.sender == address(strategist));
    }

    /**
     * @notice
     *  Only the strategist and approved keepers can call authorized
     *  functions
     */
    function _onlyKeepers() internal {
        require(
            keepers[msg.sender] == true || msg.sender == address(strategist),
            "!authorized"
        );
    }

    /**
     * @notice
     * Returns true if the debt ratio of the strategy is 0. debt ratio in this context is
     * the debt allocation of the vault, not the strategies debt ratio. 
     */
    function isInactive() public view returns (bool) {
        address vault = strategy.vault();
        ( , , uint256 debtRatio, , , , , ,) = IVault(vault).strategies(address(strategy));
        return (debtRatio == 0);
    }

    /**
     * @notice
     * Returns true if a debt rebalance is required. 
     */
    function debtTrigger() public view returns (bool _canExec) {
        if (!isInactive()) {
            uint256 debtRatio = strategy.calcDebtRatio();
            _canExec = debtRatio > strategy.debtUpper() || debtRatio < strategy.debtLower();           
        }
    }

    /**
     * @notice
     * Returns true if a debt rebalance is required. This adds an offset of "hysteriaDebt" to the
     * debt trigger thresholds to filter noise. Google Hysterisis
     */
    function debtTriggerHysteria() public view returns (bool _canExec) {
        if (!isInactive()) {
            uint256 debtRatio = strategy.calcDebtRatio();
            _canExec = (debtRatio > (strategy.debtUpper().add(hysteriaDebt)) || debtRatio < strategy.debtLower().sub(hysteriaDebt));           
        }
    }
    
    /**
     * @notice
     * Returns true if a collateral rebalance is required. This adds an offset of "hysteriaCollateral" to the
     * collateral trigger thresholds to filter noise. 
     */
    function collatTrigger() public view returns (bool _canExec) {
        if (!isInactive()) {
            uint256 collatRatio = strategy.calcCollateral();
            _canExec = collatRatio > strategy.collatUpper() || collatRatio < strategy.collatLower();
        }
    }
    
    /**
     * @notice
     * Returns true if a collateral rebalance is required. This adds an offset of "hysteriaCollateral" to the
     * collateral trigger thresholds to filter noise. 
     */
    function collatTriggerHysteria() public view returns (bool _canExec) {
        if (!isInactive()) {
            uint256 collatRatio = strategy.calcCollateral();
            _canExec = (collatRatio > strategy.collatUpper().add(hysteriaCollateral) || collatRatio < strategy.collatLower().sub(hysteriaCollateral));
        }
    }

    function updateStrategist() external {
        strategist = strategy.strategist();
    }

    function setStrategy(address _strategy) external {
        _onlyStrategist();
        setStrategyInternal(_strategy);
    }

    function addKeeper(address _newKeeper) external {
        _onlyStrategist();
        keepers[_newKeeper] = true;
        keepersList.push(_newKeeper);
    }

    function removeKeeper(address _removeKeeper) external {
        _onlyStrategist();
        keepers[_removeKeeper] = false;
    }

    function updateHysteria(uint256 _hysteriaDebt,uint256 _hysteriaCollateral) external {
        _onlyStrategist();
        hysteriaDebt = _hysteriaDebt;
        hysteriaCollateral = _hysteriaCollateral;        
    }

    function harvestTrigger(uint256 _callCost) external view returns (bool) {
        return strategy.harvestTrigger(_callCost);
    }

    function harvest() external {
        _onlyKeepers();
        strategy.harvest();
    }

    function calcDebtRatio() external view returns (uint256) {
        return strategy.calcDebtRatio();
    }

    function rebalanceDebt() external {
        _onlyKeepers();
        strategy.rebalanceDebt();
    }

    function calcCollateral() external view returns (uint256) {
        return strategy.calcCollateral();
    }

    function rebalanceCollateral() external {
        _onlyKeepers();
        strategy.rebalanceCollateral();
    }

    function setStrategyInternal(address _strategy) internal {
        strategy = CoreStrategyAPI(_strategy);
        strategist = strategy.strategist();
    }
}

