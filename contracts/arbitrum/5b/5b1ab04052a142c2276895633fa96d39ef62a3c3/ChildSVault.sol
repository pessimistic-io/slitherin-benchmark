// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import "./ERC20Upgradeable.sol";
import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { SafeMath } from "./SafeMath.sol";
import { StableMath } from "./StableMath.sol";
import { Governable } from "./Governable.sol";
import { ISingleStrategy } from "./ISingleStrategy.sol";
import { ISwapper } from "./ISwapper.sol";
import "./Sort.sol";
import "./Array.sol";
import "./console.sol";

contract ChildSVault is ERC20Upgradeable, Governable {
    using SafeERC20 for IERC20;
    using StableMath for uint256;
    using SafeMath for uint256;

    event ChildInitialized(address _by, string _name, string _symbol, address _asset, address _parent, uint256 _parentChainId);
    event StrategyApproved(address _addr);
    event StrategyRemoved(address _addr);


    address public parent;
    uint256 public parentChainId;
    address public asset;
    address public swapper;
    address public bridge;


    struct Strategy {
        bool isSupported;
    }
    mapping(address => Strategy) internal strategies;
    address[] internal allStrategies;
    address[] public quickDepositStrategies;

    struct StrategyWithWeight {
        address strategy;
        uint256 minWeight;
        uint256 targetWeight;
        uint256 maxWeight;
        bool enabled;
        bool enabledReward;
    }
    mapping(address => uint256) public strategyWithWeightPositions;
    StrategyWithWeight[] public strategyWithWeights;
    uint256 public constant TOTAL_WEIGHT = 100000; // 100000 ~ 100%
    struct Order {
        bool stake;
        address strategy;
        uint256 amount;
    }



    function initialize(
        string memory _name,
        string memory _symbol,
        address _asset,
        address _parent,
        uint256 _parentChainId
    ) external initializer {
        __ERC20_init(_name, _symbol);
        parent = _parent;
        asset = _asset;
        parentChainId = _parentChainId;
        emit ChildInitialized(msg.sender, _name, _symbol, _asset, _parent, _parentChainId);
    }

    // Modifiers
    modifier onlyParent() {
        require(msg.sender == parent, "Only parent");
        _;
    }
    modifier onlyParentOrGovernor() {
        require(msg.sender == parent || msg.sender == governor(), "Only parent or governor");
        _;
    }

    // Strategy
    /**
     * @dev Add a strategy to the Vault.
     * @param _addr Address of the strategy to add
     */
    function approveStrategy(address _addr) external onlyGovernor {
        require(!strategies[_addr].isSupported, "STRAT_APRVD");
        strategies[_addr] = Strategy({ isSupported: true });
        allStrategies.push(_addr);
        emit StrategyApproved(_addr);
    }

    /**
    * @dev Remove a strategy from the Vault.
    * @param _addr Address of the strategy to remove
    */
    function removeStrategy(address _addr) external onlyGovernor {
        require(strategies[_addr].isSupported, "Strategy not approved");
        uint256 strategyIndex = Array.remove(allStrategies, _addr);
        if (strategyIndex < allStrategies.length) {
            // Mark the strategy as not supported
            strategies[_addr].isSupported = false;
            // Withdraw all assets
            ISingleStrategy strategy = ISingleStrategy(_addr);
            strategy.withdrawAll();
        }
        Array.remove(quickDepositStrategies, _addr);
        strategyIndex = strategyWithWeights.length;
        for (uint256 i = 0; i < strategyWithWeights.length; i++) {
            if (strategyWithWeights[i].strategy == _addr) {
                strategyIndex = i;
                break;
            }
        }

        if (strategyIndex < strategyWithWeights.length) {
            strategyWithWeights[strategyIndex] = strategyWithWeights[
                strategyWithWeights.length - 1
            ];
            strategyWithWeights.pop();
            delete strategyWithWeightPositions[_addr];
        }
        emit StrategyRemoved(_addr);
    }
    /**
     * @dev Withdraws all assets from the strategy and sends assets to the Vault.
     * @param _strategyAddr Strategy address.
     */
    function withdrawAllFromStrategy(address _strategyAddr)
        external
        onlyGovernor
    {
        require(
            strategies[_strategyAddr].isSupported,
            "Strategy is not supported"
        );
        ISingleStrategy strategy = ISingleStrategy(_strategyAddr);
        strategy.withdrawAll();
    }

    /**
     * @dev Withdraws all assets from all the strategies and sends assets to the Vault.
     */
    function withdrawAllFromStrategies() external onlyGovernor {
        for (uint256 i = 0; i < allStrategies.length; i++) {
            ISingleStrategy strategy = ISingleStrategy(allStrategies[i]);
            strategy.withdrawAll();
        }
    }

    /*************************************
              Startegies Weights
    *************************************/
    
    function sortWeightsByTarget(StrategyWithWeight[] memory weights) internal pure returns(StrategyWithWeight[] memory) {
        uint[] memory targets = new uint[](weights.length);
        for(uint i = 0; i < weights.length; i++) {
            targets[i] = weights[i].targetWeight;
        }
        uint[] memory indices = new uint[](targets.length);
        for (uint z = 0; z < indices.length; z++) {
            indices[z] = z;
        }
        Sort.quickSort(targets, 0, int(targets.length-1), indices);
        StrategyWithWeight[] memory sorted = new StrategyWithWeight[](targets.length);
        for (uint z = 0; z < indices.length; z++) {
            sorted[z] = weights[indices[z]];
        }
        return sorted;
    }
    function setStrategyWithWeights(StrategyWithWeight[] calldata _strategyWithWeights) external onlyGovernor {
        uint256 totalTarget = 0;
        for (uint8 i = 0; i < _strategyWithWeights.length; i++) {
            StrategyWithWeight memory strategyWithWeight = _strategyWithWeights[i];
            require(strategyWithWeight.strategy != address(0), "weight without strategy");
            require(
                strategyWithWeight.minWeight <= strategyWithWeight.targetWeight,
                "minWeight shouldn't higher than targetWeight"
            );
            require(
                strategyWithWeight.targetWeight <= strategyWithWeight.maxWeight,
                "targetWeight shouldn't higher than maxWeight"
            );
            totalTarget += strategyWithWeight.targetWeight;
        }
        require(totalTarget == TOTAL_WEIGHT, "Total target should equal to TOTAL_WEIGHT");
        StrategyWithWeight[] memory sorted = sortWeightsByTarget(_strategyWithWeights);
        for (uint8 i = 0; i < sorted.length; i++) {
            _addStrategyWithWeightAt(sorted[i], i);
            strategyWithWeightPositions[strategyWithWeights[i].strategy] = i;
        }
        // truncate if need
        if (strategyWithWeights.length > sorted.length) {
            uint256 removeCount = strategyWithWeights.length - sorted.length;
            for (uint8 i = 0; i < removeCount; i++) {
                strategyWithWeights.pop();
            }
        }
    }
    function _addStrategyWithWeightAt(StrategyWithWeight memory strategyWithWeight, uint256 index) internal {
        uint256 currentLength = strategyWithWeights.length;
        // expand if need
        if (currentLength == 0 || currentLength - 1 < index) {
            uint256 additionalCount = index - currentLength + 1;
            for (uint8 i = 0; i < additionalCount; i++) {
                strategyWithWeights.push();
            }
        }
        strategyWithWeights[index] = strategyWithWeight;
    }
    function getStrategyWithWeight(address strategy) public view returns (StrategyWithWeight memory) {
        return strategyWithWeights[strategyWithWeightPositions[strategy]];
    }

    function getAllStrategyWithWeights() public view returns (StrategyWithWeight[] memory) {
        return strategyWithWeights;
    }

    /*********************************
                BRIDGE
    **********************************/
    function setBridge(address _bridge) external onlyGovernor {
        bridge = _bridge;
    }

    /***********************************
                setSwapper
    ************************************/
    function setSwapper(address _swapper) external onlyGovernor {
        swapper = _swapper;
    }

    /***********************************
            QuickDepositStrategies
    ************************************/
   /**
    * @dev Set the quick deposit strategies for quickAllocation of funds.
    * @param _quickDepositStrategies Array of pre-appproved startegy addresses
    */
    function setQuickDepositStrategies(address[] calldata _quickDepositStrategies) external onlyGovernor {
        for (uint8 i = 0; i < _quickDepositStrategies.length; i++) {
            require(strategies[_quickDepositStrategies[i]].isSupported, "STRT_NT_APRVD");
        }
        quickDepositStrategies = _quickDepositStrategies;
    }

    function getAllStrategies() external view returns (address[] memory) {
        return allStrategies;
    }

    /***************************
            REBALANCE
    ****************************/
    function rebalance() external onlyGovernor {
        _rebalance();
    }
     /**
    * @dev Rebalance the Vault with predefined weights
    */
    function _rebalance() internal {
        IERC20 subjectAsset = IERC20(asset);
        StrategyWithWeight[] memory stratsWithWeights = getAllStrategyWithWeights();
        require(stratsWithWeights.length > 0, "WGT NT SET");

        // 1. calc total USDC equivalent
        uint256 totalAssetInStrat = 0;
        uint256 totalWeight = 0;
        for (uint8 i; i < stratsWithWeights.length; i++) {
            if (!stratsWithWeights[i].enabled) {// Skip if strategy is not enabled
                continue;
            }

            // UnstakeFull from stratsWithWeights with targetWeight == 0
            if(stratsWithWeights[i].targetWeight == 0){
                ISingleStrategy(stratsWithWeights[i].strategy).withdrawAll();
            }else {
                totalAssetInStrat += ISingleStrategy(stratsWithWeights[i].strategy).balance();
                totalWeight += stratsWithWeights[i].targetWeight;
            }

        }
        uint256 totalAsset = totalAssetInStrat + subjectAsset.balanceOf(address(this));

        // 3. calc diffs for stratsWithWeights liquidity
        Order[] memory stakeOrders = new Order[](stratsWithWeights.length);
        uint8 stakeOrdersCount = 0;
        uint256 stakeRequirement = 0;
        for (uint8 i; i < stratsWithWeights.length; i++) {

            if (!stratsWithWeights[i].enabled) {// Skip if strategy is not enabled
                continue;
            }

            uint256 targetLiquidity;
            if (stratsWithWeights[i].targetWeight == 0) {
                targetLiquidity = 0;
            } else {
                targetLiquidity = (totalAsset * stratsWithWeights[i].targetWeight) / totalWeight;
            }

            uint256 currentLiquidity = ISingleStrategy(stratsWithWeights[i].strategy).balance();
            if (targetLiquidity == currentLiquidity) {
                // skip already at target stratsWithWeights
                continue;
            }

            if (targetLiquidity < currentLiquidity) {
                // unstake now
                ISingleStrategy(stratsWithWeights[i].strategy).withdraw(
                    address(this),
                    currentLiquidity - targetLiquidity
                );
            } else {
                // save to stake later
                stakeOrders[stakeOrdersCount] = Order(
                    true,
                    stratsWithWeights[i].strategy,
                    targetLiquidity - currentLiquidity
                );
                stakeOrdersCount++;
                stakeRequirement += targetLiquidity - currentLiquidity;
            }
        }
        console.log("REBALANCE: Balance available to stake %s", subjectAsset.balanceOf(address(this)));
        console.log("REBALANCE: Balance required to stake %s", stakeRequirement);
        // 4.  make staking
        for (uint8 i; i < stakeOrdersCount; i++) {

            address strategy = stakeOrders[i].strategy;
            uint256 amount = stakeOrders[i].amount;

            uint256 currentBalance = subjectAsset.balanceOf(address(this));
            if (currentBalance < amount) {
                amount = currentBalance;
            }
            subjectAsset.transfer(strategy, amount);

            ISingleStrategy(strategy).deposit(
                amount
            );
        }

    }

    /*************************
    *         BALANCE
    *************************/
    function balance()
        public
        view
        returns (uint256 fbalance)
    {
        fbalance = available();
        for (uint256 i = 0; i < allStrategies.length; i++) {
            ISingleStrategy strategy = ISingleStrategy(allStrategies[i]);
            fbalance = fbalance.add(strategy.balance());
        }
    }
    function available() public view returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }
    function tvl() public pure returns (uint256) {
        return 0;
    }
}
