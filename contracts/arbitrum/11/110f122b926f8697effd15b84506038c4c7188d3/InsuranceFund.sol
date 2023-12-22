// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.9;

import { IERC20 } from "./IERC20.sol";
import { OwnableUpgradeableSafe } from "./OwnableUpgradeableSafe.sol";
import { IInsuranceFund } from "./IInsuranceFund.sol";
import { BlockContext } from "./BlockContext.sol";
import { IAmm } from "./IAmm.sol";
import { UIntMath } from "./UIntMath.sol";
import { IntMath } from "./IntMath.sol";
import { TransferHelper } from "./TransferHelper.sol";
import { IInsuranceFundCallee } from "./IInsuranceFundCallee.sol";
import { IETHStakingPool } from "./IETHStakingPool.sol";
import { IClearingHouse } from "./IClearingHouse.sol";
import { Math } from "./Math.sol";

contract InsuranceFund is IInsuranceFund, OwnableUpgradeableSafe, BlockContext {
    using UIntMath for uint256;
    using IntMath for int256;
    using TransferHelper for IERC20;

    //**********************************************************//
    //    The below state variables can not change the order    //
    //**********************************************************//

    mapping(address => bool) private ammMap;
    mapping(address => bool) private quoteTokenMap;
    IAmm[] private amms;
    IERC20[] public quoteTokens;

    // contract dependencies;
    address private beneficiary;

    // amm => budget of the insurance fund, allocated to each market
    mapping(IAmm => uint256) public budgetsAllocated;

    address public ethStakingPool;

    address public tttStakingPool;

    // used to calculate the minimum insurance fund reserve amount for each collection
    uint8 public reserveCoeff;

    uint256[50] private __gap;

    //**********************************************************//
    //    The above state variables can not change the order    //
    //**********************************************************//

    //◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤ add state variables below ◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤//

    //◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣ add state variables above ◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣//

    //
    // EVENTS
    //

    event Withdrawn(address withdrawer, uint256 amount);
    event TokenAdded(address tokenAddress);
    event TokenRemoved(address tokenAddress);
    event ShutdownAllAmms(uint256 blockNumber);
    event AmmAdded(address amm);
    event AmmRemoved(address amm);

    //
    // FUNCTIONS
    //

    function initialize() public initializer {
        __Ownable_init();
        reserveCoeff = 1;
    }

    /**
     * @dev only owner can call
     * @param _amm IAmm address
     */
    function addAmm(IAmm _amm) public onlyOwner {
        require(!isExistedAmm(_amm), "IF_AAA"); //amm already added
        ammMap[address(_amm)] = true;
        amms.push(_amm);
        emit AmmAdded(address(_amm));

        // add token if it's new one
        IERC20 token = _amm.quoteAsset();
        if (!_isQuoteTokenExisted(token)) {
            quoteTokens.push(token);
            quoteTokenMap[address(token)] = true;
            emit TokenAdded(address(token));
        }
    }

    /**
     * @dev only owner can call. no need to call
     * @param _amm IAmm address
     */
    function removeAmm(IAmm _amm) external onlyOwner {
        require(isExistedAmm(_amm), "IF_ANE"); //amm not existed
        ammMap[address(_amm)] = false;
        uint256 ammLength = amms.length;
        for (uint256 i = 0; i < ammLength; i++) {
            if (amms[i] == _amm) {
                amms[i] = amms[ammLength - 1];
                amms.pop();
                emit AmmRemoved(address(_amm));
                break;
            }
        }
    }

    /**
     * @notice shutdown all Amms when fatal error happens
     * @dev only owner can call. Emit `ShutdownAllAmms` event
     */
    function shutdownAllAmm() external onlyOwner {
        for (uint256 i; i < amms.length; i++) {
            amms[i].shutdown();
        }
        emit ShutdownAllAmms(block.number);
    }

    function removeToken(IERC20 _token) external onlyOwner {
        require(_isQuoteTokenExisted(_token), "IF_TNE"); //token not existed

        quoteTokenMap[address(_token)] = false;
        uint256 quoteTokensLength = getQuoteTokenLength();
        for (uint256 i = 0; i < quoteTokensLength; i++) {
            if (quoteTokens[i] == _token) {
                if (i < quoteTokensLength - 1) {
                    quoteTokens[i] = quoteTokens[quoteTokensLength - 1];
                }
                quoteTokens.pop();
                break;
            }
        }

        // transfer the quoteToken to owner.
        if (_balanceOf(_token) > 0) {
            _token.safeTransfer(owner(), _balanceOf(_token));
        }

        emit TokenRemoved(address(_token));
    }

    function setBeneficiary(address _beneficiary) external onlyOwner {
        require(_beneficiary != address(0), "IF_ZA");
        beneficiary = _beneficiary;
    }

    /**
     * @notice activate the usage of ETH staking pool, can be called only by owner
     * @param _pool the address of the staking pool
     */
    function activateETHStakingPool(address _pool) external onlyOwner {
        require(_pool != address(0), "IF_ZA");
        ethStakingPool = _pool;
    }

    /**
     * @notice deactivate the usage of the ETH staking pool, can be called only by owner
     */
    function deactivateETHStakingPool() external onlyOwner {
        ethStakingPool = address(0);
    }

    /**
     * @notice decide how much insurance fund should be bigger, at least 1 times than vault
     */
    function setReserveCoeff(uint8 _coeff) external onlyOwner {
        require(_coeff >= 1, "IF_IC"); //invalid coefficient
        reserveCoeff = _coeff;
    }

    /**
     * @notice withdraw token to vault to cover cost, can be called only by the clearing house
     * cost is covered as follows if the staking pool has been activated
     * 1. if there is reward, it is used first
     * 2. if it is still not enough, this insurance fund is used
     * 3. if it is also still not enough, the staking principal is used
     * if the staking pool has not been activated
     * all is covered by this insurance fund
     */
    function withdraw(IAmm _amm, uint256 _amount) external override {
        uint256 budget = budgetsAllocated[_amm];
        IERC20 quoteToken = _amm.quoteAsset();
        require(beneficiary == _msgSender(), "IF_NB"); //not beneficiary
        require(_isQuoteTokenExisted(quoteToken), "IF_ANS"); //asset not supported
        address _ethStakingPool = ethStakingPool;
        if (_ethStakingPool != address(0) && quoteToken == IETHStakingPool(_ethStakingPool).quoteToken()) {
            // check reward
            uint256 amountCoveredByReward;
            int256 reward = IETHStakingPool(_ethStakingPool).calculateTotalReward();
            if (reward > 0) {
                amountCoveredByReward = Math.min(_amount, reward.abs());
            }
            // check this insurance fund
            uint256 amountCoveredByIF;
            if (_amount > amountCoveredByReward && budget > 0) {
                amountCoveredByIF = Math.min(_amount - amountCoveredByReward, budget);
                budgetsAllocated[_amm] -= amountCoveredByIF;
            }
            // check the eth staking pool
            uint256 amountCoveredByStakingPrincipal;
            if (_amount > amountCoveredByReward + amountCoveredByIF) {
                amountCoveredByStakingPrincipal = _amount - amountCoveredByReward - amountCoveredByIF;
            }

            if (amountCoveredByReward + amountCoveredByStakingPrincipal > 0) {
                IETHStakingPool(_ethStakingPool).withdraw(_amm, amountCoveredByReward + amountCoveredByStakingPrincipal);
            }
        } else {
            require(budget >= _amount, "IF_FNE"); //fund not enough
            budgetsAllocated[_amm] -= _amount;
        }
        quoteToken.safeTransfer(_msgSender(), _amount);
        emit Withdrawn(_msgSender(), _amount);
    }

    /**
     * @notice deposited token is distributed to this insurance fund and the staking pool as follows
     * if the staking pool has been activated
     * 1. staking principal is replenished first
     * 2. tribe3 reserve (insurance fund) is replenished up to vault * K
     * 3. the remain amount is distributed as reward
     * if the staking pool has not been activated
     * all fund is deposited to this insurance fund
     */
    function deposit(IAmm _amm, uint256 _amount) external override {
        IERC20 quoteToken = _amm.quoteAsset();
        require(_isQuoteTokenExisted(quoteToken), "IF_ANS"); //asset not supported
        uint256 balanceBefore = quoteToken.balanceOf(address(this));
        IInsuranceFundCallee(_msgSender()).depositCallback(quoteToken, _amount);
        _amount = quoteToken.balanceOf(address(this)) - balanceBefore;
        address _ethStakingPool = ethStakingPool;
        if (_ethStakingPool != address(0) && quoteToken == IETHStakingPool(_ethStakingPool).quoteToken()) {
            // replenish the staking principal if it has been activated
            uint256 amountToStakingPool;
            int256 reward = IETHStakingPool(_ethStakingPool).calculateTotalReward();
            if (reward < 0) {
                amountToStakingPool = Math.min(_amount, reward.abs());
            }
            // replenish this insurance fund
            uint256 amountToInsuranceFund;
            if (_amount > amountToStakingPool) {
                uint256 budget = budgetsAllocated[_amm];
                uint256 reserveAmount = IClearingHouse(beneficiary).getVaultFor(_amm) * reserveCoeff;
                if (reserveAmount > budget) {
                    amountToInsuranceFund = Math.min(_amount - amountToStakingPool, reserveAmount - budget);
                    budgetsAllocated[_amm] += amountToInsuranceFund;
                }
            }
            // distribute the remain amount as reward to the eth staking pool if it has been activated
            uint256 amountToReward;
            if (_amount > amountToStakingPool + amountToInsuranceFund) {
                amountToReward = _amount - amountToStakingPool - amountToInsuranceFund;
            }
            // transfer reward and principal replenishment to the eth staking pool
            if (amountToStakingPool + amountToReward > 0) {
                quoteToken.safeTransfer(_ethStakingPool, amountToStakingPool + amountToReward);
            }
        } else {
            budgetsAllocated[_amm] += _amount;
        }
    }

    //
    // VIEW
    //

    function getQuoteTokenLength() public view returns (uint256) {
        return quoteTokens.length;
    }

    function isExistedAmm(IAmm _amm) public view override returns (bool) {
        return ammMap[address(_amm)];
    }

    function getAllAmms() external view override returns (IAmm[] memory) {
        return amms;
    }

    function getAvailableBudgetFor(IAmm _amm) external view override returns (uint256 budget) {
        budget = budgetsAllocated[_amm];
        address _ethStakingPool = ethStakingPool;
        if (_ethStakingPool != address(0)) {
            IClearingHouse clearingHouse = IClearingHouse(beneficiary);
            uint256 currentVault = clearingHouse.getVaultFor(_amm);
            IERC20 quoteToken = _amm.quoteAsset();
            uint256 totalVault = quoteToken.balanceOf(address(clearingHouse));
            uint256 balanceOfStakingPool = quoteToken.balanceOf(_ethStakingPool);
            if (totalVault != 0) {
                budget += Math.mulDiv(balanceOfStakingPool, currentVault, totalVault);
            }
        }
    }

    //
    // private
    //

    function _isQuoteTokenExisted(IERC20 _token) internal view returns (bool) {
        return quoteTokenMap[address(_token)];
    }

    function _balanceOf(IERC20 _quoteToken) internal view returns (uint256) {
        return _quoteToken.balanceOf(address(this));
    }
}

