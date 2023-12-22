// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./SafeMathUpgradeable.sol";
import "./ERC20Upgradeable.sol";
import "./PausableUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./UUPSUpgradeable.sol";
import "./Initializable.sol";

import "./AddressStorage.sol";

// Pool
import "./IPool.sol";
import "./IERC20.sol";

import "./ISyntheX.sol";
import "./Errors.sol";
import "./SyntheXStorage.sol";
// ERC165Upgradeable
import "./ERC165Upgradeable.sol";
import "./AccessControlUpgradeable.sol";

/**
 * @title SyntheX
 * @author SyntheX
 * @custom:security-contact prasad@chainscore.finance
 * @notice This contract connects with debt pools to allows users to mint synthetic assets backed by collateral assets.
 * @dev Handles Reward Distribution: setPoolSpeed, claimReward
 * @dev Handle collateral: deposit/withdraw, enable/disable collateral, set collateral cap, volatility ratio
 * @dev Enable/disale trading pool, volatility ratio 
 */
contract SyntheX is 
    Initializable,
    ISyntheX, 
    SyntheXStorage, 
    AddressStorage, 
    AccessControlUpgradeable, 
    PausableUpgradeable, 
    UUPSUpgradeable
{
    /// @notice Using SafeERC20 for ERC20 to avoid reverts
    using SafeERC20Upgradeable for ERC20Upgradeable;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract
     * @param _l0Admin The address of the L0 admin
     * @param _l1Admin The address of the L1 admin
     * @param _l2Admin The address of the L2 admin
     */
    function initialize(
        address _l0Admin, address _l1Admin, address _l2Admin
    ) public initializer {
        __Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();
        // Set the admin roles
        _setupRole(DEFAULT_ADMIN_ROLE, _l0Admin);
        _setupRole(L1_ADMIN_ROLE, _l1Admin);
        _setupRole(L2_ADMIN_ROLE, _l2Admin);
        _setRoleAdmin(L2_ADMIN_ROLE, L1_ADMIN_ROLE);
    }

    ///@notice required by the OZ UUPS module
    function _authorizeUpgrade(address) internal override onlyL1Admin {}

    function isL0Admin(address _account) public override view returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, _account);
    }

    function isL1Admin(address _account) public override view returns (bool) {
        return hasRole(L1_ADMIN_ROLE, _account);
    }

    function isL2Admin(address _account) public override view returns (bool) {
        return hasRole(L2_ADMIN_ROLE, _account);
    }

    modifier onlyL1Admin() {
        require(isL1Admin(msg.sender), Errors.CALLER_NOT_L1_ADMIN);
        _;
    }

    modifier onlyL2Admin() {
        require(isL2Admin(msg.sender), Errors.CALLER_NOT_L2_ADMIN);
        _;
    }

    // Supports ISyntheX interface
    function supportsInterface(bytes4 interfaceId) public view virtual override(ISyntheX, AccessControlUpgradeable) returns (bool) {
        return interfaceId == type(ISyntheX).interfaceId || super.supportsInterface(interfaceId);
    }

    function vault() external override view returns(address) {
        return getAddress(VAULT);
    }

    /* -------------------------------------------------------------------------- */
    /*                               Admin Functions                              */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice Pause the contract
     * @dev Only callable by L2 admin
     */
    function pause() public onlyL2Admin {
        _pause();
    }

    /**
     * @notice Unpause the contract
     * @dev Only callable by L2 admin
     */
    function unpause() public onlyL2Admin {
        _unpause();
    }

    function setAddress(bytes32 _key, address _value) external onlyL1Admin {
        _setAddress(_key, _value);

        emit AddressUpdated(_key, _value);
    }

    /* -------------------------------------------------------------------------- */
    /*                             Reward Distribution                            */
    /* -------------------------------------------------------------------------- */
    /**
     * @dev Update pool reward index, And distribute rewards to the account
     * @param _account The account to distribute rewards for
     * @param _totalSupply The total debt supply of the pool
     * @param _balance The debt balance of the account in the pool
     * @dev This function is called by the trading pool
     */
    function distribute(address _account, uint _totalSupply, uint _balance) external override whenNotPaused {
        address[] memory _rewardTokens = rewardTokens[msg.sender];
        _updatePoolRewardIndex(_rewardTokens, msg.sender, _totalSupply);
        _distributeAccountReward(_rewardTokens, msg.sender,  _account, _balance);
    }

    /**
     * @dev Update pool reward index only
     * @param _totalSupply The total debt supply of the pool
     * @dev This function is called by the trading pool
     */
    function distribute(uint _totalSupply) external override whenNotPaused {
        address[] memory _rewardTokens = rewardTokens[msg.sender];
        _updatePoolRewardIndex(_rewardTokens, msg.sender, _totalSupply);
    }

    /**
     * @dev Set the reward speed for a trading pool
     * @param _rewardToken The reward token
     * @param _pool The address of the trading pool
     * @param _speed The reward speed
     */
    function setPoolSpeed(address _rewardToken, address _pool, uint _speed, bool _addToList) virtual public onlyL2Admin {
        // update existing rewards
        address[] memory _rewardTokens = new address[](1);
        _rewardTokens[0] = _rewardToken;
        _updatePoolRewardIndex(_rewardTokens, _pool, IERC20(payable(_pool)).totalSupply());
        // set speed
        rewardSpeeds[_rewardToken][_pool] = _speed;
        // add to list
        if(_addToList) {
            // override existing list
            address[] memory _rewardTokens = rewardTokens[_pool];
            // make sure it doesn't already exist
            for(uint i = 0; i < _rewardTokens.length; i++) {
                require(_rewardTokens[i] != _rewardToken, Errors.ASSET_ALREADY_ADDED);
            }
            rewardTokens[_pool].push(_rewardToken);
        }
        // emit successful event
        emit SetPoolRewardSpeed(_rewardToken, _pool, _speed); 
    }

    function removeRewardToken(address _rewardToken, address _pool) external onlyL2Admin {
        address[] memory _rewardTokens = rewardTokens[_pool];
        for(uint i = 0; i < _rewardTokens.length; i++) {
            if(_rewardTokens[i] == _rewardToken) {
                _rewardTokens[i] = _rewardTokens[_rewardTokens.length - 1];
                rewardTokens[_pool].pop();
                break;
            }
        }
    }
    
    /**
     * @notice Accrue rewards to the market
     * @param _rewardTokens The reward token
     */
    function _updatePoolRewardIndex(address[] memory _rewardTokens, address _pool, uint _totalSupply) internal {
        for(uint i = 0; i < _rewardTokens.length; i++) {
            address _rewardToken = _rewardTokens[i];
            if(_rewardToken == address(0)) return;
            PoolRewardState storage poolRewardState = rewardState[_rewardToken][_pool];
            uint rewardSpeed = rewardSpeeds[_rewardToken][_pool];
            uint deltaTimestamp = block.timestamp - poolRewardState.timestamp;
            if (deltaTimestamp > 0 && rewardSpeed > 0) {
                uint synAccrued = deltaTimestamp * rewardSpeed;
                uint ratio = _totalSupply > 0 ? synAccrued * rewardInitialIndex / _totalSupply : 0;
                poolRewardState.index = uint224(poolRewardState.index + ratio);
                poolRewardState.timestamp = uint32(block.timestamp);
            }
            else if (deltaTimestamp > 0) {
                poolRewardState.timestamp = uint32(block.timestamp);
            }
        }
    }

    /**
     * @notice Calculate reward accrued by a supplier and possibly transfer it to them
     * @param _rewardTokens The reward token
     * @param _account The address of the supplier to distribute reward to
     */
    function _distributeAccountReward(address[] memory _rewardTokens, address _pool, address _account, uint _balance) internal {
        uint[] memory accountDeltas = new uint[](_rewardTokens.length);
        uint[] memory borrowIndexes = new uint[](_rewardTokens.length);
        for(uint i = 0; i < _rewardTokens.length; i++) {
            address _rewardToken = _rewardTokens[i];
            if(_rewardToken == address(0)) return;
            // This check should be as gas efficient as possible as distributeAccountReward is called in many places.
            // - We really don't want to call an external contract as that's quite expensive.

            PoolRewardState storage poolRewardState = rewardState[_rewardToken][_pool];
            uint borrowIndex = poolRewardState.index;
            uint accountIndex = rewardIndex[_rewardToken][_pool][_account];

            // Update supplier's index to the current index since we are distributing accrued esSYX
            rewardIndex[_rewardToken][_pool][_account] = borrowIndex;

            if (accountIndex == 0 && borrowIndex >= rewardInitialIndex) {
                // Covers the case where users supplied tokens before the market's supply state index was set.
                // Rewards the user with reward accrued from the start of when supplier rewards were first
                // set for the market.
                accountIndex = rewardInitialIndex; // 1e36
            }

            // Calculate change in the cumulative sum of the esSYX per debt token accrued
            uint deltaIndex = borrowIndex - accountIndex;

            // Calculate reward accrued: cTokenAmount * accruedPerCToken
            uint accountDelta = _balance * deltaIndex / rewardInitialIndex;

            uint accountAccrued = rewardAccrued[_rewardToken][_account] + (accountDelta);
            rewardAccrued[_rewardToken][_account] = accountAccrued;

            accountDeltas[i] = accountDelta;
            borrowIndexes[i] = borrowIndex;
        }

        emit DistributedReward(_rewardTokens, _pool, _account, accountDeltas, borrowIndexes);
    }

    /**
     * @notice Claim all SYN accrued by the holders
     * @param _rewardTokens The address of the reward token
     * @param holder The addresses to claim esSYX for
     * @param _pools The list of markets to claim esSYX in
     */
    function claimReward(address[] memory _rewardTokens, address holder, address[] memory _pools) virtual override public {
        // Iterate through all holders and trading pools
        for (uint i = 0; i < _pools.length; i++) {
            // Iterate thru all reward tokens
            _updatePoolRewardIndex(_rewardTokens, _pools[i], IERC20(payable(_pools[i])).totalSupply());
            _distributeAccountReward(_rewardTokens, _pools[i], holder, IERC20(payable(_pools[i])).balanceOf(holder));
        } 
        for (uint i = 0; i < _rewardTokens.length; i++) {
            uint amount = rewardAccrued[_rewardTokens[i]][holder];
            rewardAccrued[_rewardTokens[i]][holder] = amount - (transferOut(_rewardTokens[i], holder, amount));
        }
    }

    /**
     * @dev Get total $SYN accrued by an account
     * @dev Only for getting dynamic reward amount in frontend. To be statically called
     */
    function getRewardsAccrued(address[] memory _rewardTokens, address holder, address[] memory _pools) virtual override public returns(uint[] memory) {
        // Iterate over all the trading pools and update the reward index and account's reward amount
        for (uint i = 0; i < _pools.length; i++) {
            // Iterate thru all reward tokens
            _updatePoolRewardIndex(_rewardTokens, _pools[i], IERC20(payable(_pools[i])).totalSupply());
            _distributeAccountReward(_rewardTokens, _pools[i], holder, IERC20(payable(_pools[i])).balanceOf(holder));
        }
        // Get the rewards accrued
        uint[] memory rewardsAccrued = new uint[](_rewardTokens.length); 
        for (uint i = 0; i < _rewardTokens.length; i++) {
            rewardsAccrued[i] = rewardAccrued[_rewardTokens[i]][holder];
        }
        return rewardsAccrued;
    }

    /**
     * @notice Transfer asset out to address
     * @param _asset The address of the asset
     * @param recipient The address of the recipient
     * @param _amount Amount
     * @return The amount transferred
     */
    function transferOut(address _asset, address recipient, uint _amount) internal returns(uint) {
        if(ERC20Upgradeable(_asset).balanceOf(address(this)) < _amount){
            _amount = ERC20Upgradeable(_asset).balanceOf(address(this));
        }
        ERC20Upgradeable(_asset).safeTransfer(recipient, _amount);

        return _amount;
    }
}
