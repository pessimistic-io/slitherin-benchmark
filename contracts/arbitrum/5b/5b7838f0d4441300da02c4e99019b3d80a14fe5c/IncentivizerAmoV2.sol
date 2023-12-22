// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

// ====================================================================
// |     ______                   _______                             |
// |    / _____________ __  __   / ____(_____  ____ _____  ________   |
// |   / /_  / ___/ __ `| |/_/  / /_  / / __ \/ __ `/ __ \/ ___/ _ \  |
// |  / __/ / /  / /_/ _>  <   / __/ / / / / / /_/ / / / / /__/  __/  |
// | /_/   /_/   \__,_/_/|_|  /_/   /_/_/ /_/\__,_/_/ /_/\___/\___/   |
// |                                                                  |
// ====================================================================
// ====================== IncentivizerAmoV2 ===========================
// ====================================================================
// Frax Finance: https://github.com/FraxFinance
// This Contract will be used for STIP Grant distribution 
// Whats new? tier based incentive calculation model  

// Primary Author(s)
// Amirnader Aghayeghazvini: https://github.com/amirnader-ghazvini

// Reviewer(s) / Contributor(s)
// Dennis: https://github.com/denett

import "./IFrax.sol";
import "./IFxs.sol";
import "./IIncentivizationHandler.sol";
import "./TransferHelper.sol";
import "./ERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";

contract IncentivizerAmoV2 is Ownable {
/* ============================================= STATE VARIABLES ==================================================== */

    // Addresses Config
    address public operatorAddress;
    address public targetTokenAddress; // Token that AMO incentivize
    address public incentiveTokenAddress; // Token that AMO uses as an incentive

    // Pools related
    address[] public poolArray; // List of pool addresses
    struct LiquidityPool {
        // Pool Addresses
        address poolAddress; // Where the actual tokens are in the pool
        address lpTokenAddress; // Pool LP token address
        address incentivePoolAddress; // Contract that handle incentive distribution e.g. Bribe contract
        address incentivizationHandlerAddress; // Incentive handler contract e.g. votemarket handler
        address gaugeAddress; // Gauge address
        uint256 incentivizationId; // Votemarket Bounty ID
        bool isPaused;
        uint lastIncentivizationTimestamp; // timestamp of last time this pool was incentivized
        uint lastIncentivizationAmount; // Max amount of incentives
        uint firstIncentivizationTimestamp; // timestamp of the first incentivization
        uint poolCycleLength; // length of the cycle for this pool in sec (e.g. one week)
    }
    mapping(address => bool) public poolInitialized;
    mapping(address => LiquidityPool) private poolInfo;

    // Constant Incentivization can be set (e.g. DAO Deal)
    mapping(address => bool) public poolHasFixedIncent; 
    mapping(address => uint256) public poolFixedIncentAmount; // Constant Incentivization amount

    // Pool tiers  
    struct IncentiveTier {
        uint256 tokenMaxBudgetPerUnit; // Max incentive per unit of target token per cycle for pools within this tier
        uint256 kickstartPeriodLength; // Kickstart period length for pools within this tier in secs
        uint256 kickstartPeriodBudget; // Kickstart period budget per cycle for pools within this tier 
    }
    IncentiveTier[] public tierArray;
    mapping(address => uint) public poolTier;

    // Configurations
    uint256 public minTvl; // Min TVL of pool for being considered for incentivization
    uint256 public cycleStart; // timestamp of cycle start
    uint256 public cycleLength; // length of the cycle in sec (e.g. one week)

/* =============================================== CONSTRUCTOR ====================================================== */

    /// @notice constructor
    /// @param _operatorAddress Address of AMO Operator
    /// @param _targetTokenAddress Address of Token that AMO incentivize (e.g. crvFRAX)
    /// @param _incentiveTokenAddress Address of Token that AMO uses as an incentive (e.g. FXS)
    /// @param _minTvl Min TVL of pool for being considered for incentivization
    /// @param _cycleStart timestamp of cycle start
    /// @param _cycleLength length of the cycle (e.g. one week)
    constructor(
        address _operatorAddress,
        address _targetTokenAddress,
        address _incentiveTokenAddress,
        uint256 _minTvl,
        uint256 _cycleStart,
        uint256 _cycleLength
    ) Ownable() {
        operatorAddress = _operatorAddress;
        targetTokenAddress = _targetTokenAddress;
        incentiveTokenAddress = _incentiveTokenAddress;
        minTvl = _minTvl;
        require(_cycleStart < block.timestamp, "Cycle start time error");
        cycleStart = _cycleStart;
        cycleLength = _cycleLength;
        addTier(0, 0, 0);
        emit StartAMO(_operatorAddress, _targetTokenAddress, _incentiveTokenAddress);
    }

/* ================================================ MODIFIERS ======================================================= */

    modifier onlyByOwnerOperator() {
        require(msg.sender == operatorAddress || msg.sender == owner(), "Not owner or operator");
        _;
    }

    modifier activePool(address _poolAddress) {
        require(poolInitialized[_poolAddress] && !poolInfo[_poolAddress].isPaused, "Pool is not active");
        require(showPoolTvl(_poolAddress) > minTvl, "Pool is small");
        _;
    }

/* ================================================= EVENTS ========================================================= */

    /// @notice The ```StartAMO``` event fires when the AMO deploys
    /// @param _operatorAddress Address of operator
    /// @param _targetTokenAddress Address of Token that AMO incentivize (e.g. crvFRAX)
    /// @param _incentiveTokenAddress Address of Token that AMO uses as an incentive (e.g. FXS)
    event StartAMO(address _operatorAddress, address _targetTokenAddress, address _incentiveTokenAddress);

    /// @notice The ```SetOperator``` event fires when the operatorAddress is set
    /// @param _oldAddress The original address
    /// @param _newAddress The new address
    event SetOperator(address _oldAddress, address _newAddress);

    /// @notice The ```AddOrSetPool``` event fires when a pool is added or modified
    /// @param _poolAddress The pool address
    /// @param _lpTokenAddress The pool LP token address
    /// @param _gaugeAddress The gauge address
    /// @param _incentivePoolAddress Contract that handle incentive distribution e.g. Bribe contract
    /// @param _incentivizationHandlerAddress Incentive handler contract e.g. votemarket handler
    /// @param _indexId indexID in Votium or Votemarket
    /// @param _poolCycleLength length of the cycle for this pool in sec (e.g. one week)
    event AddOrSetPool(
        address _poolAddress,
        address _lpTokenAddress,
        address _gaugeAddress,
        address _incentivePoolAddress,
        address _incentivizationHandlerAddress,
        uint256 _indexId,
        uint256 _poolCycleLength
    );

    /// @notice The ```AddOrSetTier``` event fires when a pool is added or modified
    /// @param _tierId Index of the incentivization tier
    /// @param _tokenMaxBudgetPerUnit  Max incentive per unit of target token per cycle for pools within this tier
    /// @param _kickstartPeriodLength Kickstart period length for pools within this tier in sec
    /// @param _kickstartPeriodBudget Kickstart period budget per cycle for pools within this tier
    event AddOrSetTier(uint256 _tierId,uint256 _tokenMaxBudgetPerUnit,uint256 _kickstartPeriodLength,uint256 _kickstartPeriodBudget);

    /// @notice The ```ChangePauseStatusPool``` event fires when a pool is added or modified
    /// @param _poolAddress The pool address
    /// @param _isPaused Pool Pause Status
    event ChangePauseStatusPool(address _poolAddress, bool _isPaused);

    /// @notice The ```SetPoolFixedIncent``` event fires when a pool's constant incentivization is updated 
    /// @param _poolAddress The pool address
    /// @param _hasFixedIncent Pool Deal Status
    /// @param _amountPerCycle Pool Deal Amount
    event SetPoolFixedIncent(address _poolAddress, bool _hasFixedIncent, uint256 _amountPerCycle);

    /// @notice The ```SetPoolTier``` event fires when a pool's incentivization tier change
    /// @param _poolAddress The pool address
    /// @param _tierId Index of the incentivization tier
    event SetPoolTier(address _poolAddress, uint256 _tierId);

    /// @notice The ```IncentivizePool``` event fires when a deposit happens to a pair
    /// @param _poolAddress The pool address
    /// @param _amount Incentive amount
    event IncentivizePool(address _poolAddress, uint256 _amount);

/* ================================================== VIEWS ========================================================= */

    /// @notice Returns the total number of pools added
    /// @return _length uint256 Number of pools added
    function allPoolsLength() public view returns (uint256 _length) {
        return poolArray.length;
    }

    /// @notice Returns the total number of tiers added
    /// @return _length uint256 Number of tiers added
    function allTiersLength() public view returns (uint256 _length) {
        return tierArray.length;
    }
    
    /// @notice Show TVL of targeted token in all active pools
    /// @return TVL of targeted token in all active pools
    function showActivePoolsTvl() public view returns (uint256) {
        uint tvl = 0;
        for (uint i = 0; i < poolArray.length; i++) {
            if (!poolInfo[poolArray[i]].isPaused) {
                tvl += showPoolTvl(poolArray[i]);
            }
        }
        return tvl;
    }

    /// @notice Show TVL of targeted token in liquidity pool
    /// @param _poolAddress Address of liquidity pool
    /// @return TVL of targeted token in liquidity pool
    function showPoolTvl(address _poolAddress) public view returns (uint256) {
        ERC20 targetToken = ERC20(targetTokenAddress);
        return targetToken.balanceOf(_poolAddress);
    }

    /// @notice Show Pool parameters
    /// @param _poolAddress Address of liquidity pool
    /// @return _gaugeAddress Gauge Contract Address
    /// @return _incentivePoolAddress Contract that handle incentive distribution e.g. Bribe contract
    /// @return _incentivizationHandlerAddress Incentive handler contract e.g. votemarket handler
    /// @return _incentivizationId Pool General Incentivization ID (e.g. in Votemarket it is BountyID)
    /// @return _poolCycleLength length of the cycle for this pool in sec (e.g. one week)
    function showPoolInfo(
        address _poolAddress
    )
        external
        view
        returns (
            address _gaugeAddress,
            address _incentivePoolAddress,
            address _incentivizationHandlerAddress,
            uint256 _incentivizationId,
            uint256 _poolCycleLength
        )
    {
        _incentivePoolAddress = poolInfo[_poolAddress].incentivePoolAddress;
        _incentivizationHandlerAddress = poolInfo[_poolAddress].incentivizationHandlerAddress;
        _gaugeAddress = poolInfo[_poolAddress].gaugeAddress;
        _incentivizationId = poolInfo[_poolAddress].incentivizationId;
        _poolCycleLength = poolInfo[_poolAddress].poolCycleLength;
    }

    /// @notice Show Pool status
    /// @param _poolAddress Address of liquidity pool
    /// @return _isInitialized Pool registered or not
    /// @return _lastIncentivizationTimestamp timestamp of last time this pool was incentivized
    /// @return _lastIncentivizationAmount last cycle incentive amount
    /// @return _isPaused puased or not
    function showPoolStatus(
        address _poolAddress
    )
        external
        view
        returns (
            bool _isInitialized,
            uint _lastIncentivizationTimestamp,
            uint _lastIncentivizationAmount,
            bool _isPaused
        )
    {
        _isInitialized = poolInitialized[_poolAddress];
        _lastIncentivizationTimestamp = poolInfo[_poolAddress].lastIncentivizationTimestamp;
        _lastIncentivizationAmount = poolInfo[_poolAddress].lastIncentivizationAmount;
        _isPaused = poolInfo[_poolAddress].isPaused;
    }

    /// @notice Show Tier Info
    /// @param _tierId Tier Index
    /// @return _tokenMaxBudgetPerUnit  Max incentive per unit of target token per cycle for pools within this tier
    /// @return _kickstartPeriodLength Kickstart period length for pools within this tier in secs
    /// @return _kickstartPeriodBudget Kickstart period budget per cycle for pools within this tier 
    /// @return _numberOfPools Number of pools in this tier
    function showTierInfo(
        uint256 _tierId
    )
        external
        view
        returns (
            uint256 _tokenMaxBudgetPerUnit,
            uint256 _kickstartPeriodLength,
            uint256 _kickstartPeriodBudget,
            uint256 _numberOfPools 
        )
    {
        _tokenMaxBudgetPerUnit = tierArray[_tierId].tokenMaxBudgetPerUnit;
        _kickstartPeriodLength = tierArray[_tierId].kickstartPeriodLength;
        _kickstartPeriodBudget = tierArray[_tierId].kickstartPeriodBudget;
        uint numberOfPools = 0;
        for (uint i = 0; i < poolArray.length; i++) {
            if (!poolInfo[poolArray[i]].isPaused) {
                if (poolTier[poolArray[i]] == _tierId) {
                    numberOfPools += 1;
                }
            }
        }
        _numberOfPools = numberOfPools;
    }

    /// @notice Show Pool Kickstart Period status
    /// @param _poolAddress Address of liquidity pool
    /// @return _isInKickstartPeriod Pool registered or not
    function isPoolInKickstartPeriod(
        address _poolAddress
    )
        public
        view
        returns (
            bool _isInKickstartPeriod
        )
    {
        if (poolInfo[_poolAddress].firstIncentivizationTimestamp == 0){
            _isInKickstartPeriod = true;
        } else {
            uint256 tier = poolTier[_poolAddress];
            uint256 firstIncentiveCycleBegin = cycleStart + (((poolInfo[_poolAddress].firstIncentivizationTimestamp - cycleStart) / cycleLength) * cycleLength);
            uint256 delta = (block.timestamp - firstIncentiveCycleBegin);
            if (delta > tierArray[tier].kickstartPeriodLength) {
                _isInKickstartPeriod = false;
            } else {
                _isInKickstartPeriod = true;
            }
        }
    }

    /// @notice Show if Pool incentivized within the current cycle 
    /// @param _poolAddress Address of liquidity pool
    /// @return _isIncentivized Pool incentivized or not
    function isPoolIncentivizedAtCycle(
        address _poolAddress
    )
        public
        view
        returns (
            bool _isIncentivized
        )
    {
        if (poolInfo[_poolAddress].lastIncentivizationTimestamp == 0) {
            _isIncentivized = false;
        } else {
            uint256 currentCycle = ((block.timestamp - cycleStart) / poolInfo[_poolAddress].poolCycleLength) + 1;
            uint256 lastIncentiveCycle = ((poolInfo[_poolAddress].lastIncentivizationTimestamp - cycleStart) / poolInfo[_poolAddress].poolCycleLength) + 1;
            if (lastIncentiveCycle < currentCycle){
                _isIncentivized = false;
            } else {
                _isIncentivized = true;
            }
        }
        
    }

    /// @notice Function to calculate max incentive budget for one pool (based on tier budgets)
    /// @param _poolAddress Address of liquidity pool
    /// @return _amount max incentive budget for the pool in target token
    function maxBudgetForPoolByTier(address _poolAddress) public view returns (uint256 _amount) {
        uint256 _poolTvl = showPoolTvl(_poolAddress);
        uint256 _tierId = poolTier[_poolAddress];
        uint256 _cycleRatio = (poolInfo[_poolAddress].poolCycleLength * 100_000) / cycleLength ;
        uint256 _kickstartPeriodBudget = 0;
        uint256 _maxUintBasedBudget = (tierArray[_tierId].tokenMaxBudgetPerUnit * _poolTvl) / (10 ** ERC20(targetTokenAddress).decimals());
        if(isPoolInKickstartPeriod(_poolAddress)){
            _kickstartPeriodBudget = tierArray[_tierId].kickstartPeriodBudget;
        }
        if(isPoolIncentivizedAtCycle(_poolAddress)) {
            _amount = 0;
        } else if(_kickstartPeriodBudget > _maxUintBasedBudget) {
            _amount = _kickstartPeriodBudget * _cycleRatio / 100_000;
        } else {
            _amount = _maxUintBasedBudget * _cycleRatio / 100_000;
        }        
    }

    /// @notice Function to calculate max incentive budget for all pools (based on tier budgets)
    /// @return _totalMaxBudget max incentive budget for all pools in target token
    function maxBudgetForAllPoolsByTier() public view returns (uint256 _totalMaxBudget) {
        _totalMaxBudget = 0;
        for (uint256 i = 0; i < poolArray.length; i++) {
            _totalMaxBudget += maxBudgetForPoolByTier(poolArray[i]);
        }
    }

    /// @notice Function to calculate adjusted incentive budget for one pool (based on tier budgets)
    /// @param _poolAddress Address of liquidity pool
    /// @param _totalIncentAmount Total Incentive budget in incetive token
    /// @param _totalMaxIncentiveAmount Total max Incentive budget in target token
    /// @param _priceRatio (Target Token Price / Incentive Token Price) * 100_000
    /// @return _amount adjusted incentive budget for one pool in incentive token 
    function adjustedBudgetForPoolByTier(address _poolAddress, uint256 _totalIncentAmount, uint256 _totalMaxIncentiveAmount, uint256 _priceRatio) public view returns (uint256 _amount) {
        uint256 _poolMaxBudget = maxBudgetForPoolByTier(_poolAddress) * _priceRatio / 100_000;
        uint256 _totalMaxIncentive = _totalMaxIncentiveAmount * _priceRatio / 100_000;
        if (_totalIncentAmount > _totalMaxIncentive) {
            _amount = _poolMaxBudget;
        } else if (_totalMaxIncentive > 0){
            _amount = (_poolMaxBudget * _totalIncentAmount) / _totalMaxIncentive;
        } else {
            _amount = 0;
        }
    }

/* ======================================== INCENTIVIZATION FUNCTIONS =============================================== */

    /// @notice Function to deposit incentives to one pool
    /// @param _poolAddress Address of liquidity pool
    /// @param _amount Amount of incentives to be deposited
    function incentivizePoolByAmount(
        address _poolAddress,
        uint256 _amount
    ) public activePool(_poolAddress) onlyByOwnerOperator {
        ERC20 _incentiveToken = ERC20(incentiveTokenAddress);
        _incentiveToken.approve(poolInfo[_poolAddress].incentivePoolAddress, _amount);

        (bool success, ) = poolInfo[_poolAddress].incentivizationHandlerAddress.delegatecall(
            abi.encodeWithSignature(
                "incentivizePool(address,address,address,address,uint256,uint256)",
                _poolAddress,
                poolInfo[_poolAddress].gaugeAddress,
                poolInfo[_poolAddress].incentivePoolAddress,
                incentiveTokenAddress,
                poolInfo[_poolAddress].incentivizationId,
                _amount
            )
        );
        require(success, "delegatecall failed");
        if (poolInfo[_poolAddress].lastIncentivizationTimestamp == 0){
            poolInfo[_poolAddress].firstIncentivizationTimestamp = block.timestamp;
        }
        poolInfo[_poolAddress].lastIncentivizationTimestamp = block.timestamp;
        poolInfo[_poolAddress].lastIncentivizationAmount = _amount;
        emit IncentivizePool(_poolAddress, _amount);
    }

    /// @notice Function to deposit incentives to one pool (based on ratio)
    /// @param _poolAddress Address of liquidity pool
    /// @param _totalIncentAmount Total budget for incentivization
    /// @param _totalTvl Total active pools TVL
    function incentivizePoolByTvl(
        address _poolAddress,
        uint256 _totalIncentAmount,
        uint256 _totalTvl
    ) public onlyByOwnerOperator {
        uint256 _poolTvl = showPoolTvl(_poolAddress);
        uint256 _amount = (_totalIncentAmount * _poolTvl) / _totalTvl;
        incentivizePoolByAmount(_poolAddress, _amount);
    }

    /// @notice Function to deposit incentives to one pool (based on budget per unit)
    /// @param _poolAddress Address of liquidity pool
    /// @param _unitIncentAmount Incentive per single unit of target Token
    function incentivizePoolByUnitBudget(
        address _poolAddress,
        uint256 _unitIncentAmount
    ) public onlyByOwnerOperator {
        uint256 _poolTvl = showPoolTvl(_poolAddress);
        uint256 _amount = (_unitIncentAmount * _poolTvl) / (10 ** ERC20(targetTokenAddress).decimals());
        incentivizePoolByAmount(_poolAddress, _amount);
    }

    /// @notice Function to deposit incentives to one pool (based on Constant Incentivization)
    /// @param _poolAddress Address of liquidity pool
    function incentivizePoolByFixedIncent(
        address _poolAddress
    ) public onlyByOwnerOperator {
        if (poolHasFixedIncent[_poolAddress]){
            uint256 _amount = poolFixedIncentAmount[_poolAddress];
            incentivizePoolByAmount(_poolAddress, _amount);
        }
    }

    /// Functions For depositing incentives to all active pools

    /// @notice Function to deposit incentives to all active pools (based on TVL ratio)
    /// @param _totalIncentAmount Total Incentive budget
    /// @param _FixedIncent Incentivize considering FixedIncent
    function incentivizeAllPoolsByTvl(uint256 _totalIncentAmount, bool _FixedIncent) public onlyByOwnerOperator {
        uint256 _totalTvl = showActivePoolsTvl();
        for (uint i = 0; i < poolArray.length; i++) {
            if (_FixedIncent && poolHasFixedIncent[poolArray[i]]) {
                incentivizePoolByFixedIncent(poolArray[i]);
            } else if (!poolInfo[poolArray[i]].isPaused && showPoolTvl(poolArray[i]) > minTvl) {
                incentivizePoolByTvl(poolArray[i], _totalIncentAmount, _totalTvl);
            }
        }
    }
    
    /// @notice Function to deposit incentives to all active pools (based on budget per unit of target Token)
    /// @param _unitIncentAmount Incentive per single unit of target Token
    /// @param _FixedIncent Incentivize considering FixedIncent
    function incentivizeAllPoolsByUnitBudget(uint256 _unitIncentAmount, bool _FixedIncent) public onlyByOwnerOperator {
        for (uint i = 0; i < poolArray.length; i++) {
            if (_FixedIncent && poolHasFixedIncent[poolArray[i]]) {
                incentivizePoolByFixedIncent(poolArray[i]);
            } else if (!poolInfo[poolArray[i]].isPaused && showPoolTvl(poolArray[i]) > minTvl) {
                incentivizePoolByUnitBudget(poolArray[i], _unitIncentAmount);
            }
        }
    }

    /// @notice Add/Set liquidity pool
    /// @param _poolAddress Address of liquidity pool
    /// @param _incentivePoolAddress Contract that handle incentive distribution e.g. Bribe contract
    /// @param _incentivizationHandlerAddress Incentive handler contract e.g. votemarket handler
    /// @param _gaugeAddress Address of liquidity pool gauge
    /// @param _lpTokenAddress Address of liquidity pool lp token
    /// @param _incentivizationId Pool General Incentivization ID (e.g. in Votemarket it is BountyID)
    /// @param _poolCycleLength length of the cycle for this pool in sec (e.g. one week)
    function addOrSetPool(
        address _poolAddress,
        address _incentivePoolAddress,
        address _incentivizationHandlerAddress,
        address _gaugeAddress,
        address _lpTokenAddress,
        uint256 _incentivizationId,
        uint256 _poolCycleLength
    ) external onlyByOwnerOperator {
        if (poolInitialized[_poolAddress]) {
            poolInfo[_poolAddress].incentivePoolAddress = _incentivePoolAddress;
            poolInfo[_poolAddress].incentivizationHandlerAddress = _incentivizationHandlerAddress;
            poolInfo[_poolAddress].gaugeAddress = _gaugeAddress;
            poolInfo[_poolAddress].incentivizationId = _incentivizationId;
            poolInfo[_poolAddress].lpTokenAddress = _lpTokenAddress;
            poolInfo[_poolAddress].poolCycleLength = _poolCycleLength;
        } else {
            poolInitialized[_poolAddress] = true;
            poolArray.push(_poolAddress);
            poolInfo[_poolAddress] = LiquidityPool({
                poolAddress: _poolAddress,
                lpTokenAddress: _lpTokenAddress,
                incentivePoolAddress: _incentivePoolAddress,
                incentivizationHandlerAddress: _incentivizationHandlerAddress,
                gaugeAddress: _gaugeAddress,
                lastIncentivizationTimestamp: 0,
                lastIncentivizationAmount: 0,
                firstIncentivizationTimestamp: 0,
                isPaused: false,
                incentivizationId: _incentivizationId,
                poolCycleLength: _poolCycleLength
            });
            setPoolTier(_poolAddress, 0);
        }

        emit AddOrSetPool(
            _poolAddress,
            _lpTokenAddress,
            _gaugeAddress,
            _incentivePoolAddress,
            _incentivizationHandlerAddress,
            _incentivizationId,
            _poolCycleLength
        );
    }

    /// @notice Pause/Unpause liquidity pool
    /// @param _poolAddress Address of liquidity pool
    /// @param _isPaused bool
    function pausePool(address _poolAddress, bool _isPaused) external onlyByOwnerOperator {
        if (poolInitialized[_poolAddress]) {
            poolInfo[_poolAddress].isPaused = _isPaused;
            emit ChangePauseStatusPool(_poolAddress, _isPaused);
        }
    }

    /// @notice Add/Change/Remove Constant Incentivization can be set (e.g. DAO Deal)
    /// @param _poolAddress Address of liquidity pool
    /// @param _hasFixedIncent bool
    /// @param _amountPerCycle Amount of constant incentives
    function setFixedIncent(address _poolAddress, bool _hasFixedIncent, uint256 _amountPerCycle) external onlyByOwnerOperator {
        if (poolInitialized[_poolAddress]) {
            poolHasFixedIncent[_poolAddress] = _hasFixedIncent;
            poolFixedIncentAmount[_poolAddress] = _amountPerCycle;
            emit SetPoolFixedIncent(_poolAddress, _hasFixedIncent, _amountPerCycle);
        }
    }

/* ================================== TIER BASED INCENTIVIZATION FUNCTIONS ========================================== */

    /// @notice Add/Set a Incentivization Tier
    /// @param _tokenMaxBudgetPerUnit  Max incentive per unit of target token per cycle for pools within this tier
    /// @param _kickstartPeriodLength Kickstart period length for pools within this tier in secs
    /// @param _kickstartPeriodBudget Kickstart period budget per cycle for pools within this tier 
    function addTier(
        uint256 _tokenMaxBudgetPerUnit,
        uint256 _kickstartPeriodLength,
        uint256 _kickstartPeriodBudget
    ) public onlyByOwnerOperator returns (uint256 _tierId) {
        _tierId = allTiersLength();
        tierArray.push(IncentiveTier({
            tokenMaxBudgetPerUnit: _tokenMaxBudgetPerUnit,
            kickstartPeriodLength: _kickstartPeriodLength,
            kickstartPeriodBudget: _kickstartPeriodBudget
        }));
        emit AddOrSetTier(_tierId, _tokenMaxBudgetPerUnit, _kickstartPeriodLength, _kickstartPeriodBudget);
    }

    /// @notice Set liquidity pool incentivization tier
    /// @param _poolAddress Address of liquidity pool
    /// @param _tierId uint256
    function setPoolTier(address _poolAddress, uint256 _tierId) public onlyByOwnerOperator {
        if (poolInitialized[_poolAddress] && (_tierId < allTiersLength())) {
            poolTier[_poolAddress] = _tierId;
            emit SetPoolTier(_poolAddress, _tierId);
        }
    }

    /// @notice Function to deposit incentives to all pools (based on tier budgets)
    /// @param _totalIncentAmount Total Incentive budget in incentive token
    /// @param _priceRatio (Target Token Price / Incentive Token Price) * 100_000  
    function incentivizeAllPoolsByTier(uint256 _totalIncentAmount, uint256 _priceRatio) public onlyByOwnerOperator {
        uint256 _totalMaxIncentiveAmount = maxBudgetForAllPoolsByTier();
        for (uint i = 0; i < poolArray.length; i++) {
            uint256 _amount = adjustedBudgetForPoolByTier(poolArray[i], _totalIncentAmount, _totalMaxIncentiveAmount, _priceRatio);
            incentivizePoolByAmount(poolArray[i], _amount);
        }
    }


/* ====================================== RESTRICTED GOVERNANCE FUNCTIONS =========================================== */

    /// @notice Change the Operator address
    /// @param _newOperatorAddress Operator address
    function setOperatorAddress(address _newOperatorAddress) external onlyOwner {
        emit SetOperator(operatorAddress, _newOperatorAddress);
        operatorAddress = _newOperatorAddress;
    }

    /// @notice Change the Cycle Length for incentivization
    /// @param _cycleLength Cycle Length for being considered for incentivization
    function setCycleLength(uint256 _cycleLength) external onlyOwner {
        cycleLength = _cycleLength;
    }

    /// @notice Change the Min TVL for incentivization
    /// @param _minTvl Min TVL of pool for being considered for incentivization
    function setMinTvl(uint256 _minTvl) external onlyOwner {
        minTvl = _minTvl;
    }

    /// @notice Recover ERC20 tokens
    /// @param tokenAddress address of ERC20 token
    /// @param tokenAmount amount to be withdrawn
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        // Can only be triggered by owner
        TransferHelper.safeTransfer(address(tokenAddress), msg.sender, tokenAmount);
    }

    // Generic proxy
    function execute(
        address _to,
        uint256 _value,
        bytes calldata _data
    ) external onlyOwner returns (bool, bytes memory) {
        (bool success, bytes memory result) = _to.call{ value: _value }(_data);
        return (success, result);
    }
}
