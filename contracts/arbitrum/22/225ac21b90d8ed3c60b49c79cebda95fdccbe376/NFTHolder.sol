// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./IVotingEscrow.sol";
import "./IFeeDistributor.sol";
import "./IGauge.sol";
import "./IVoter.sol";
import "./IRewarder.sol";
import "./IPoolFactory.sol";
import "./IVeDepositor.sol";
import "./INeadStake.sol";

import "./PausableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./AccessControlEnumerableUpgradeable.sol";
import "./Initializable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./ISwappoor.sol";

contract LpDepositor is
    Initializable,
    AccessControlEnumerableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /* ========== STATE VARIABLES ========== */

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant VOTER_ROLE = keccak256("VOTER_ROLE");

    // Ramses contracts
    IVotingEscrow public votingEscrow;
    IVoter public voter;
    address ram;

    // Ennead contracts
    address public neadRam;
    uint public tokenID;
    address public neadStake;

    // pool -> gauge
    mapping(address => address) public gaugeForPool;
    // pool -> deposit token
    mapping(address => address) public tokenForPool;

    // reward variables
    uint public platformFee; // initially set to 15%
    uint treasuryFee; // initially set to 5%
    uint stakerFee; // initially set to 10%
    address public platformFeeReceiver;
    // token -> unclaimed fee
    mapping(address => uint) unclaimedFees;

    address public poolFactory;
    uint public feeNotifyThreshold;
    
    
    event Deposited(address indexed user, address indexed pool, uint amount);
    event Withdrawn(address indexed user, address indexed pool, uint amount);
    event FeesNotified(address indexed token, uint treasuryShare, uint stakerShare);
    ISwappoor swap;
    // to prevent approving the swapper to spend a token more than once
    mapping(address => bool) isApproved;
    // the token to swap to and notify for stakers
    address swapTo;
    // bribe claim notify fee
    uint callFee;
    
    

    /* ========== CONSTRUCTOR ========== */

    constructor() {
        _disableInitializers();
        }

    function initialize(
        IVotingEscrow _votingEscrow,
        IVoter _voter,
        address admin,
        address pauser,
        address setter,
        address operator,
        address voterRole
            ) public initializer {
        __Pausable_init();
        __ReentrancyGuard_init();
        __AccessControlEnumerable_init();

        votingEscrow = _votingEscrow;
        voter = _voter;
        ram = IVoter(_voter).base();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, pauser);
        _grantRole(SETTER_ROLE, setter);
        _grantRole(OPERATOR_ROLE, operator);
        _grantRole(VOTER_ROLE, voterRole);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function onERC721Received(
        address _operator,
        address _from,
        uint _tokenID,
        bytes calldata
    ) external whenNotPaused returns (bytes4) {
        // VeDepositor transfers the NFT to this contract so this callback is required
        require(_operator == neadRam);

        // make sure only voting escrow can call this method
        require(msg.sender == address(votingEscrow));

        if (tokenID == 0) {
            tokenID = _tokenID;
        }

        return
            bytes4(
                keccak256("onERC721Received(address,address,uint256,bytes)")
            );
    }

    // @dev user balance data is not stored in this contract, all accounting is handled by the specific `pool`'s rewarder.
    function deposit(address pool, uint amount) external whenNotPaused nonReentrant {
        require(tokenID != 0, "Must lock Ram first");

        address gauge = gaugeForPool[pool];

        if (gauge == address(0)) {
            gauge = voter.gauges(pool);
            if (gauge == address(0)) {
                gauge = voter.createGauge(pool);
            }
            gaugeForPool[pool] = gauge;
            tokenForPool[pool] = _deployDepositToken(pool);
            IERC20Upgradeable(pool).approve(gauge, type(uint).max);
        }

        IERC20Upgradeable(pool).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
        IGauge(gauge).deposit(amount, tokenID);
        IRewarder(tokenForPool[pool]).stakeFor(msg.sender, amount);

        emit Deposited(msg.sender, pool, amount);
    }

    // @dev user balance data is not stored in this contract, all accounting is handled by the specific `pool`'s rewarder.
    function withdraw(address pool, uint amount) external whenNotPaused nonReentrant {
        address gauge = gaugeForPool[pool];

        require(gauge != address(0), "Unknown pool");

        IRewarder(tokenForPool[pool]).withdraw(msg.sender, amount);
        IGauge(gauge).withdraw(amount);
        IERC20Upgradeable(pool).safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, pool, amount);
    }

     // @notice returns pending rewards earned by the protocol per pool
    function pendingRewards(address pool, address reward) external view returns (uint) {
        address gauge = gaugeForPool[pool];
        uint _reward = IGauge(gauge).earned(reward, address(this));
        return _reward;
    }

    // @notice claims rewards from Ramses and sends to Rewarder
    function claimRewards(address pool, address reward) external {
        address gauge = gaugeForPool[pool];
        address poolToken = tokenForPool[pool];
        require(msg.sender == poolToken);
        IERC20Upgradeable _reward = IERC20Upgradeable(reward);
        
        address[] memory rewards = new address[](1);
        rewards[0] = reward;
        
        uint _delta = _reward.balanceOf(address(this));
        IGauge(gauge).getReward(address(this), rewards);
        // gas savings, balance will never be lower than previous balance after a getReward
        unchecked {
            _delta = _reward.balanceOf(address(this)) - _delta;
        }
        
        if(_delta > 0) {
            unchecked {
                uint fee = _delta * platformFee / 1e18;
                _delta -= fee;
                _reward.safeTransfer(msg.sender, _delta);
                unclaimedFees[reward] += fee;
            }
        }

        if(unclaimedFees[reward] > feeNotifyThreshold) {
            _notifyPerformanceFees(reward);
        }

    }

    // @notice claims rewards for user per pool
    function getReward(address[] calldata pool) external {
        
        uint len = pool.length;

        for (uint i; i < len; ++i) {
            IRewarder _pool = IRewarder(tokenForPool[pool[i]]);
            _pool.getReward(msg.sender);
        }
    }

    // @notice claims rewards for user per pool and swaps/locks to neadRam
    function claim(address[] calldata pool) external {
        uint len = pool.length;
        uint bal;
        bool state;
        uint amountOut;
        for(uint i; i < len; ++i) {
            IRewarder _pool = IRewarder(tokenForPool[pool[i]]);
            _pool.claim(msg.sender);
            bal = IERC20Upgradeable(ram).balanceOf(address(this)) - unclaimedFees[ram];
            state = swap.priceOutOfSync();
            if(state) {
                amountOut = swap.swapTokens(ram, neadRam, bal);
                IERC20Upgradeable(neadRam).transfer(msg.sender, amountOut);
            } else {
                IVeDepositor(neadRam).depositTokens(bal);
                IERC20Upgradeable(neadRam).transfer(msg.sender, bal);
            }
        }
    }


    // @notice sends performance fees to treasury and stakers, this function is purely altruistic; there is no reward for calling this.
    function notifyPerformanceFees(address[] calldata tokens) external {
        uint len = tokens.length;

        for (uint i; i < len; ++i) {
            _notifyPerformanceFees(tokens[i]);
        }
    }


    /* ========== RESTRICTED FUNCTIONS ========== */

    function setAddresses(
        address _neadRam,
        address _platformFeeReceiver,
        address _neadStake,
        address _poolFactory
            ) external onlyRole(SETTER_ROLE) {
        if (_neadRam != address(0)) {
            neadRam = _neadRam;
            votingEscrow.setApprovalForAll(neadRam, true); // for merge
            IERC20Upgradeable(ram).approve(_neadRam, type(uint).max);
        }

        if (_platformFeeReceiver != address(0)) platformFeeReceiver = _platformFeeReceiver;

        if(_neadStake != address(0)){
            neadStake = _neadStake;
            IERC20Upgradeable(neadRam).approve(_neadStake, type(uint).max);
        } 

        if(_poolFactory != address(0)) poolFactory = _poolFactory;
    }

    // just separating this from setAddresses for ease
    function setSwapper(address _swapper) external onlyRole(SETTER_ROLE) {
        swap = ISwappoor(_swapper);
        IERC20Upgradeable(ram).approve(_swapper, type(uint).max); // approving ram here as it won't be approved otherwise
        if(!isApproved[ram]) isApproved[ram] = true;
    }

    // separating this too for ease
    function setToToken(address _token) external onlyRole(SETTER_ROLE) {
        swapTo = _token;
        IERC20Upgradeable(_token).approve(neadStake, type(uint).max);
    }

    // must be percent * 10**18
    function setCallFee(uint _fee) external onlyRole(SETTER_ROLE) {
        callFee = _fee;
    }
    
    function setRewardsFees(uint _platformFee, uint _treasuryFee, uint _stakersFee)
        external
        onlyRole(OPERATOR_ROLE)
    {
        platformFee = _platformFee;
        treasuryFee = _treasuryFee;
        stakerFee = _stakersFee;
        require(treasuryFee + stakerFee == platformFee, "!Total");
    }

    // @notice sets the amount of fees before they are pushed to neadRam stakers, setting to zero means there is no delay in fee notifying.
    // Although this is not ideal as different reward tokens may need different thresholds, it is assumed that most of the time Ram will be the only reward token.
    function setFeeNotifyThreshold(uint _threshold) external onlyRole(OPERATOR_ROLE) {
        feeNotifyThreshold = _threshold;
    }

    // temporary function to approve swapper to spend lpDepositor's tokens since we are moving to a new one.
    function approveSwapper(address[] calldata tokens) external onlyRole(OPERATOR_ROLE) {
        uint len = tokens.length;
        for(uint x; x < len; ++x) {
            if(isApproved[tokens[x]]) {
                IERC20Upgradeable(tokens[x]).approve(address(swap), type(uint).max);
            }
        }
    }

    function vote(address[] memory pools, uint[] memory weights)
        external
        onlyRole(VOTER_ROLE)
    {
        voter.vote(tokenID, pools, weights);
    }

    function claimBribes(
        address[] memory rewarders,
        address[][] memory tokens,
        address to
    ) external {
        INeadStake stake = INeadStake(neadStake);
        for (uint i; i < rewarders.length; i++) {
            IBribe(rewarders[i]).getReward(tokenID, tokens[i]);
            for (uint j; j < tokens[i].length; j++) {
                address _token = tokens[i][j];
                if(!isApproved[_token]) {
                        IERC20Upgradeable(_token).approve(address(swap), type(uint).max);
                    }
                uint bal = IERC20Upgradeable(_token).balanceOf(address(this));
                if(_token != ram && _token != neadRam) {
                    bal -= unclaimedFees[_token];
                    uint amountOut = swap.swapTokens(_token, swapTo, bal);
                    uint fee = amountOut * callFee / 10**18;
                    IERC20Upgradeable(swapTo).safeTransfer(to, fee);
                    stake.notifyRewardAmount(swapTo, amountOut - fee);
                    emit FeesNotified(_token, amountOut - fee, fee);
                }
                // if token is ram or neadRam bounty will be paid in neadRam
                else if(_token == ram) {
                    bal -= unclaimedFees[_token];
                    IVeDepositor(neadRam).depositTokens(bal);
                    uint fee = bal * callFee / 10**18;
                    IERC20Upgradeable(neadRam).safeTransfer(to, fee);
                    stake.notifyRewardAmount(neadRam, bal - fee);
                    emit FeesNotified(neadRam, bal - fee, fee);
                }
                else if (_token == neadRam) {
                    bal -= unclaimedFees[_token];
                    uint fee = bal * callFee / 10**18;
                    IERC20Upgradeable(_token).safeTransfer(to, fee);
                    stake.notifyRewardAmount(neadRam, bal - fee);
                    emit FeesNotified(neadRam, bal - fee, fee);
                } else { //means _token == swapTo
                    bal -= unclaimedFees[_token];
                    uint fee = bal * callFee / 10**18;
                    IERC20Upgradeable(_token).safeTransfer(to, fee);
                    stake.notifyRewardAmount(_token, bal - fee);
                    emit FeesNotified(_token, bal - fee, fee);
                }
            }
        }
    }

    function addRewardsPerPool(address[] calldata pools, address[][] calldata tokens) external onlyRole(OPERATOR_ROLE) {

        for (uint i; i < pools.length; ++i) {
            address pool = pools[i];
            address[] memory token = tokens[i];
            uint len = token.length;

            for (uint j; j < len; ++j) {
                IRewarder(pool).addRewardToken(token[j]);
                IERC20Upgradeable(token[j]).approve(address(swap), type(uint).max);
            }
            
        }

    }

    function removeRewardsPerPool(address[] calldata pools, address[][] calldata tokens) external onlyRole(OPERATOR_ROLE) {

        for (uint i; i < pools.length; ++i) {
            address pool = pools[i];
            address[] memory token = tokens[i];
            uint len = token.length;

            for (uint j; j < len; ++j) {
                IRewarder(pool).removeRewardToken(token[j]);
            }
            
        }

    }

    function setApprovalForAll(address _operator, bool _approved)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        votingEscrow.setApprovalForAll(_operator, _approved);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /* ========== INTERNAL FUNCTIONS ========== */
    function _deployDepositToken(address pool) internal returns (address token) {
        token = IPoolFactory(poolFactory).createPool(pool, ram);
    }

    function _notifyPerformanceFees(address token) internal {
        uint fee = unclaimedFees[token];
        unclaimedFees[token] = 0;

        uint treasury;
        uint stakers;
        unchecked {
            // calculate fee to treasury
            treasury = fee * treasuryFee / platformFee;
            // calculate fee to stakers
            stakers = fee * stakerFee / platformFee;

        }
        
        // transfer to treasury
        IERC20Upgradeable(token).safeTransfer(platformFeeReceiver, treasury);
        // transfer to stakers
        // if token is ram, lock to neadRam first.
        if (token == ram) {
            bool state = swap.priceOutOfSync();
            if(state) {
                uint amountOut = swap.swapTokens(ram, neadRam, stakers);
                INeadStake(neadStake).notifyRewardAmount(neadRam, amountOut);
            } else {
                IVeDepositor(neadRam).depositTokens(stakers);
                // neadRam is minted in a 1:1 ratio
                INeadStake(neadStake).notifyRewardAmount(neadRam, stakers);
            }
        } 
        else if (token == neadRam) {
            INeadStake(neadStake).notifyRewardAmount(neadRam, stakers);
        } else {
            uint amountOut = swap.swapTokens(token, swapTo, stakers);
            INeadStake(neadStake).notifyRewardAmount(swapTo, amountOut);
        }

        emit FeesNotified(token, treasury, stakers);
    }
}
// contract is already too big, ig i should have split it into more contracts... thankfully arbi doesnt have a contract size limit
