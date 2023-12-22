// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Initializable.sol";
import "./IERC20.sol";
import "./ILpDepositor.sol";


contract Rewarder is Initializable, IERC20 {

    // Reward data vars
    struct Reward {
        uint integral;
        uint delta;
    }

    // account -> token -> integral
    mapping(address => mapping(address => uint)) public rewardIntegralFor;
    // token -> integral
    mapping(address => Reward) public rewardIntegral;
    // account -> token -> claimable
    mapping(address => mapping(address => uint)) public claimable;
    // list of reward tokens
    address[] public rewards;
    mapping(address => bool) isReward;

    uint public totalSupply;
    mapping(address => uint) public balanceOf;

    // ERC20 vars
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    mapping(address => mapping(address => uint)) public allowance;

    address depositor;
    address pool;

    // events
    event TransferDeposit(address indexed from, address indexed to, uint amount);
    event RewardPaid(address indexed user, address indexed rewardsToken, uint256 reward);

    constructor() {
        _disableInitializers();
        }

    function initialize(address _pool, address _reward, address _depositor) external initializer {
        require(pool == address(0));
        pool = _pool;
        
        if (!isReward[_reward]) isReward[_reward] = true;
        rewards.push(_reward);

        depositor = _depositor;
        string memory _symbol = IERC20(pool).symbol();
        name = string(abi.encodePacked("Ennead ", _symbol, " Deposit"));
        symbol = string(abi.encodePacked("nead-", _symbol));
    }

    function stakeFor(address account, uint amount) external  {
        require(msg.sender == depositor);

        updateAllIntegrals(account);
        mint(account, amount);
        // gas savings, it's highly unlikely for totalSupply and balanceOf to exceed max uint
        unchecked {
            totalSupply += amount;
            balanceOf[account] += amount;
        }
    }

    function withdraw(address account, uint amount) external  {
        require(msg.sender == depositor);

        updateAllIntegrals(account);
        totalSupply -= amount;
        balanceOf[account] -= amount;
        burn(account, amount);
    }

    // @notice earned is an estimation and is not exact until checkpoints have actually been updated.
    function earned(address account, address[] calldata tokens) external view returns (uint[] memory) {
        uint len = tokens.length;
        uint[] memory pending = new uint[](len);
        uint bal = balanceOf[account];
        uint _totalSupply = totalSupply;
        address _pool = pool;

        if (bal > 0) {
            for(uint i; i < len; ++i) {
                pending[i] += claimable[account][tokens[i]];
                uint integral = rewardIntegral[tokens[i]].integral;

                if(totalSupply > 0) {
                uint256 delta = ILpDepositor(depositor).pendingRewards(_pool, tokens[i]);
                delta -= delta * 15 / 100;
                integral += 1e18 * delta / _totalSupply;
                }

                uint integralFor = rewardIntegralFor[account][tokens[i]];
                if (integralFor < integral) pending[i] += bal * (integral - integralFor) / 1e18;
            }
        } else {
            for(uint i; i < len; ++i) {
                 pending[i] = claimable[account][tokens[i]];
            }
        }
        return pending;
    }

    function updateAllIntegrals(address account) internal {
        // always update integrals before any balance changes
        uint len = rewards.length;
        // gas savings, only do a for loop if rewards > 1
        if(len > 1) {
            address[] memory _rewards = rewards;
            for(uint i; i < len;) {
                _updateIntegralPerReward(account, _rewards[i]);
                // gas savings, since `i` is constrained by `len`, it is impossible to overflow.
                unchecked {
                    ++i;
                }
            }
        } else {
            // ram will always be index 0. It's highly unlikely for a gauge to have other rewards without having ram too.
            _updateIntegralPerReward(account, rewards[0]);
            }
    }

    function _updateIntegralPerReward(address account, address token) internal {
        Reward memory _integral = rewardIntegral[token];
        uint total = totalSupply;

        // gas savings, delta will never be negative, and it is extremely unlikely for integral to overflow
        unchecked {
            if (total > 0) {
                uint _delta = _integral.delta;
                ILpDepositor(depositor).claimRewards(pool,token);
                uint bal = IERC20(token).balanceOf(address(this));
                _delta =  bal - _delta;

            
            if (_delta > 0) {
                _integral.integral += 1e18 * _delta / total;
                _integral.delta = bal;
                rewardIntegral[token] = _integral;
            }
        }
            if (account != address(0)) {
                uint integralFor = rewardIntegralFor[account][token];
                if (integralFor < _integral.integral) {
                    claimable[account][token] += balanceOf[account] * (_integral.integral - integralFor) / 1e18;
                    rewardIntegralFor[account][token] = _integral.integral;
                }
            }   
        } 
    }

    function getReward(address account) external {
        require(msg.sender == account || msg.sender == depositor);

        uint len = rewards.length;
        if (len > 1) {
            address[] memory _rewards = rewards;
            
            for (uint i; i < len;) {
                _updateIntegralPerReward(account, _rewards[i]);
                uint claims = claimable[account][_rewards[i]];
                unchecked {
                    rewardIntegral[_rewards[i]].delta -= claims;
                }
                delete claimable[account][rewards[i]];

                IERC20(rewards[i]).transfer(account, claims);
                emit RewardPaid(account, _rewards[i], claims);
                unchecked {
                    ++i;
                }
            }
        } else {
            address _reward = rewards[0];
            _updateIntegralPerReward(account, _reward);
            uint claims = claimable[account][_reward];
            // gas savings, balance will never go below claimable
            unchecked {
                rewardIntegral[_reward].delta -= claims;
            }
            delete claimable[account][_reward];

            IERC20(_reward).transfer(account, claims);
            emit RewardPaid(account, _reward, claims);
        }
        
    }

    /*
    * @dev separate getReward function for ram -> neadRam rewards to not break compatibility with protocols building on top
    * @dev the difference between this and getReward is this sends ram to depositor instead of directly to the user, non ram rewards are sent directly
    * @notice only the lpDepositor will be able to call this function
    */
    function claim(address account) external {
        require(msg.sender == depositor);

        uint len = rewards.length;
        if (len > 1) {
            address[] memory _rewards = rewards;
            
            for (uint i; i < len;) {
                _updateIntegralPerReward(account, _rewards[i]);
                uint claims = claimable[account][_rewards[i]];
                unchecked {
                    rewardIntegral[_rewards[i]].delta -= claims;
                }
                delete claimable[account][rewards[i]];
                if(i == 0) { // ram is always index 0
                    IERC20(rewards[i]).transfer(depositor, claims);
                } else {
                    IERC20(rewards[i]).transfer(account, claims);
                    emit RewardPaid(account, _rewards[i], claims);
                }
                unchecked {
                    ++i;
                }
            }
        } else {
            address _reward = rewards[0];
            _updateIntegralPerReward(account, _reward);
            uint claims = claimable[account][_reward];
            // gas savings, balance will never go below claimable
            unchecked {
                rewardIntegral[_reward].delta -= claims;
            }
            delete claimable[account][_reward];

            IERC20(_reward).transfer(depositor, claims); // transfer to depositor if len == 1 because ram is always index 0
        }
    }

    // @notice In case a new reward token is added, to allow distribution to stakers.
    function addRewardToken(address token) external {
        require(msg.sender == depositor);

        if(!isReward[token]) {
            isReward[token] = true;
            rewards.push(token);
        }
    }
    
    /* 
     *   @notice Remove reward tokens if there haven't been emissions to it in awhile. Saves a lot of gas on interactions.
     *   @dev Must be very careful when calling this function as users will not be able to claim rewards for the token that was removed.
     *   While there is some security measure in place, the caller must still ensure that all users have claimed rewards before this is called.
     */
    function removeRewardToken(address token) external {
        require(msg.sender == depositor);
        // 0 balance assumes each user has already claimed their rewards.
        require(IERC20(token).balanceOf(address(this)) == 0);
        // ram will always be index 0, can't remove that.
        require(token != rewards[0]);

        address[] memory _rewards = rewards;
        uint len = _rewards.length;
        uint idx;

        isReward[token] = false;

        // get reward token index
        for (uint i; i < len; ++i) {
            if (_rewards[i] == token) {
                idx = i;
            }
        }
        
        // remove from rewards list
        for (uint256 i = idx; i < len - 1; ++i) {
            rewards[i] = rewards[i + 1];
        }
        rewards.pop();

    }

    function approve(address _spender, uint _value) external returns (bool) {
        allowance[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    function transferDeposit(address from, address to, uint amount) internal returns (bool) {
        // update rewards of sender before any balance change
        updateAllIntegrals(from);
        balanceOf[from] -= amount;

        // update rewards of receiver before any balance change.
        updateAllIntegrals(to);
        unchecked {
            balanceOf[to] += amount;
        }
        emit TransferDeposit(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint amount) internal {
        require(amount > 0, "Can't transfer 0!");
        transferDeposit( from, to, amount);
        emit Transfer(from, to, amount);
    }

    function transfer(address to, uint amount) public returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

  
    function transferFrom(address from, address to, uint amount) public returns (bool) {
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        if (allowance[from][msg.sender] != type(uint).max) {
            allowance[from][msg.sender] -= amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function mint(address _to, uint _value) internal returns (bool) {
        emit Transfer(address(0), _to, _value);
        return true;
    }

    function burn(address _from, uint _value) internal returns (bool) {
        emit Transfer(_from, address(0), _value);
        return true;
    }

    function rewardsListLength() external view returns (uint) {
        return rewards.length;
    }

}

