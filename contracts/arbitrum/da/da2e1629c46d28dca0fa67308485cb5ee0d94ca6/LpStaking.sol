// SPDX-License-Identifier: MIT
/// @title LP Staking
/// @author MrD 

pragma solidity >=0.8.11;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./SafeERC20.sol";

import "./IERC20Minter.sol";
import "./PancakeLibs.sol";

import "./INftRewards.sol";

contract LpStaking is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20Minter;

    INftRewards public nftRewardsContract;

    /* @dev struct to hold the user data */
    struct UserInfo {
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 rewardDebt;     // Reward debt.
        uint256 firstStake; // timestamp of the first time this wallet stakes
    }

    struct FeeInfo {
        uint256 feePercent;         // Percent fee that applies to this range
        uint256 timeCheck; // number of seconds from the intial stake this fee applies
    }

    /* @dev struct to hold the info for each pool */
    struct PoolInfo {
        IERC20Minter lpToken;           // Address of a token contract, LP or token.
        uint256 allocPoint;       // How many allocation points assigned to this pool. 
        uint256 lastRewardBlock;  // Last block number that distribution occurs.
        uint256 accRewardsPerShare;   // Accumulated Tokens per share, times 1e12. 
        uint directStake;      // 0 = off, 1 = buy token, 2 = pair native/token, 3 = pair token/token, 
        IERC20Minter tokenA; // leave emty if native, otherwise the token to pair with tokenB
        IERC20Minter tokenB; // the other half of the LP pair
        uint256 tierMultiplier;   // rewards * tierMultiplier is how many tier points earned
        uint256 totalStakers; // number of people staked
    }


    // Global active flag
    bool public isActive;

    // swap check
    bool isSwapping;

    // add liq check
    bool isAddingLp;

    // The Token
    IERC20Minter public rewardToken;

    // Base amount of rewards distributed per block
    uint256 public rewardsPerBlock;

    // Addresses 
    address public feeAddress;

    // Info of each user that stakes LP tokens 
    PoolInfo[] public poolInfo;

    // Info about the withdraw fees
    FeeInfo[] public feeInfo;
    
    // Total allocation points. Must be the sum of all allocation points in all pools 
    uint256 public totalAllocPoint = 0;

    // The block number when rewards start 
    uint256 public startBlock;

    uint256 public minPairAmount;

    uint256 public defaultFeePercent = 100;

    // PCS router
    IPancakeRouter02 private  pancakeRouter; 

    //TODO: Change to Mainnet
    //TestNet
     address private PancakeRouter;
    //MainNet
    // address private constant PancakeRouter=0x10ED43C718714eb63d5aA57B78B54704E256024E;

    // Info of each user that stakes LP tokens
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    // @dev mapping of existing pools to avoid dupes
    mapping(IERC20Minter => bool) public pollExists;

    event SetActive( bool isActive);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetFeeAddress(address indexed user, address indexed newAddress);
    event SetFeeStructure(uint256[] feePercents, uint256[] feeTimeChecks);
    event UpdateEmissionRate(address indexed user, uint256 rewardsPerBlock);

    constructor(
        IERC20Minter _rewardToken,
        address _feeAddress,
        uint256 _rewardsPerBlock,
        uint256 _startBlock,
        INftRewards _nftRewardsContract,
        address _router,
        uint256[] memory _feePercents,
        uint256[] memory  _feeTimeChecks
    ) {
        require(_feeAddress != address(0),'Invalid Address');

        PancakeRouter = address(_router);
        rewardToken = _rewardToken;
        feeAddress = _feeAddress;
        rewardsPerBlock = _rewardsPerBlock;
        startBlock = _startBlock;

        

        pancakeRouter = IPancakeRouter02(PancakeRouter);
        rewardToken.approve(address(pancakeRouter), type(uint256).max);

        // set the initial fee structure
        _setWithdrawFees(_feePercents ,_feeTimeChecks );

        // set the nft rewards contract
        nftRewardsContract = _nftRewardsContract;

        // add the SAS staking pool
        add(400, rewardToken,  true, 4000000000000000000, 1, IERC20Minter(address(0)), IERC20Minter(address(0)));
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function setWithdrawFees( uint256[] calldata _feePercents ,uint256[] calldata  _feeTimeChecks ) public onlyOwner {
        _setWithdrawFees( _feePercents , _feeTimeChecks );
    }

    function _setWithdrawFees( uint256[] memory _feePercents ,uint256[] memory  _feeTimeChecks ) private {
        delete feeInfo;
        for (uint256 i = 0; i < _feePercents.length; ++i) {
            require( _feePercents[i] <= 2500, "fee too high");
            feeInfo.push(FeeInfo({
                feePercent : _feePercents[i],
                timeCheck : _feeTimeChecks[i]
            }));
        }
        emit SetFeeStructure(_feePercents,_feeTimeChecks);
    }

    event PoolAdded(uint256 indexed pid, uint256 allocPoint, address lpToken,uint256 tierMultiplier, uint directStake, address tokenA, address tokenB);
    /* @dev Adds a new Pool. Can only be called by the owner */
    function add(
        uint256 _allocPoint, 
        IERC20Minter _lpToken, 
        bool _withUpdate,
        uint256 _tierMultiplier, 
        uint _directStake,
        IERC20Minter _tokenA,
        IERC20Minter _tokenB
    ) public onlyOwner {
        require(pollExists[_lpToken] == false, "nonDuplicated: duplicated");
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint + _allocPoint;
        pollExists[_lpToken] = true;

        poolInfo.push(PoolInfo({
            lpToken : _lpToken,
            allocPoint : _allocPoint,
            lastRewardBlock : lastRewardBlock,
            accRewardsPerShare : 0,
            tokenA: _tokenA,
            tokenB: _tokenB,
            directStake: _directStake,
            tierMultiplier: _tierMultiplier,
            totalStakers: 0
        }));

        emit PoolAdded(poolInfo.length-1, _allocPoint, address(_lpToken), _tierMultiplier,_directStake, address(_tokenA), address(_tokenB));
    }

    /* @dev Update the given pool's allocation point and deposit fee. Can only be called by the owner */
    event PoolSet(uint256 indexed pid, uint256 allocPoint,uint256 tierMultiplier, uint directStake);
    function set(
        uint256 _pid, 
        uint256 _allocPoint, 
        bool _withUpdate, 
        uint256 _tierMultiplier,
        uint _directStake
    ) public onlyOwner {

        if (_withUpdate) {
            massUpdatePools();
        }

        totalAllocPoint = (totalAllocPoint - poolInfo[_pid].allocPoint) + _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].tierMultiplier = _tierMultiplier;
        poolInfo[_pid].directStake = _directStake;

        emit PoolSet(_pid, _allocPoint,_tierMultiplier,_directStake);
    }

    /* @dev Return reward multiplier over the given _from to _to block */
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to - _from;
    }

    /* @dev View function to see pending rewards on frontend.*/
    function pendingRewards(uint256 _pid, address _user)  external view returns (uint256) {
        return _pendingRewards(_pid, _user);
    }

    /* @dev calc the pending rewards */
    function _pendingRewards(uint256 _pid, address _user) internal view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        uint256 accRewardsPerShare = pool.accRewardsPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 tokenReward = (multiplier * rewardsPerBlock * pool.allocPoint) / totalAllocPoint;
            accRewardsPerShare = accRewardsPerShare + ((tokenReward * 1e12 / lpSupply));
        }
        return ((user.amount * accRewardsPerShare)/1e12) - user.rewardDebt;
    }

    // View function to see pending tier rewards for this pool 
    function pendingTierRewards(uint256 _pid, address _user)  external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        uint256 pending = _pendingRewards(_pid,_user);

        return pending * (pool.tierMultiplier/1 ether);
    }

    /* @dev Update reward variables for all pools. Be careful of gas spending! */
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    /* @dev Update reward variables of the given pool to be up-to-date */
    event PoolUpdated(uint256 indexed pid, uint256 accRewardsPerShare, uint256 lastRewardBlock);
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));

        if (lpSupply == 0 || pool.allocPoint == 0 || pool.totalStakers == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 tokenReward = (multiplier * rewardsPerBlock * pool.allocPoint) / totalAllocPoint;

        rewardToken.mint(feeAddress, tokenReward/10);
        rewardToken.mint(address(this), tokenReward);

        pool.accRewardsPerShare = pool.accRewardsPerShare + ((tokenReward * 1e12)/lpSupply);
        pool.lastRewardBlock = block.number;
        emit PoolUpdated(_pid, pool.accRewardsPerShare, pool.lastRewardBlock);
    }

    event Harvested(address indexed user, uint256 indexed pid, uint256 tokens, uint256 points);
    function _harvest(uint256 _pid, address _user) private {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 pending = ((user.amount * pool.accRewardsPerShare)/1e12) - user.rewardDebt;
        
        if (pending > 0) {
            uint256 points = (pending * pool.tierMultiplier)/1 ether;
            // handle updating tier points
            if(pool.tierMultiplier > 0){
                nftRewardsContract.addPoints(_user, points);
            }
            // send from the contract
            safeTokenTransfer(_user, pending);

            emit Harvested(_user,_pid,pending,points);
        }
    }

    function multiHarvest(uint256[] calldata _pids) public nonReentrant {
        _multiHarvest(msg.sender, _pids);
    }

    function _multiHarvest(address _user, uint256[] calldata _pids) private {

        for (uint256 i = 0; i < _pids.length; ++i) {
            if(userInfo[i][_user].amount > 0){
                updatePool(_pids[i]);
                _harvest(_pids[i],_user);
                userInfo[i][_user].rewardDebt = (userInfo[i][_user].amount * poolInfo[_pids[i]].accRewardsPerShare)/1e12;
            }
        }
    }

    function multiCompound(uint256[] calldata _pids) public nonReentrant {
        uint256 startBalance = rewardToken.balanceOf(msg.sender);
        for (uint256 i = 0; i < _pids.length; ++i) {
            _multiHarvest(msg.sender, _pids);
        }
        uint256 toCompound = rewardToken.balanceOf(msg.sender) - startBalance;
        _deposit(0,toCompound,msg.sender,false);
    }


    event Compounded(address indexed user, uint256 pid, uint256 amount);
    function compound(uint256 _pid) public nonReentrant {
        uint256 startBalance = rewardToken.balanceOf(msg.sender);
        _deposit(_pid,0,msg.sender,false);
        uint256 toCompound = rewardToken.balanceOf(msg.sender) - startBalance;
        _deposit(0,toCompound,msg.sender,false);
        emit Compounded(msg.sender,_pid,toCompound);
    }
   /* function compound(uint256 _pid) public nonReentrant {
        uint256 startBalance = rewardToken.balanceOf(msg.sender);
        updatePool(_pid);
         _harvest(_pid,msg.sender);
        uint256 toCompound = rewardToken.balanceOf(msg.sender) - startBalance;
        _deposit(0,toCompound,msg.sender,false);
        emit Compounded(msg.sender,_pid,toCompound);
    }*/


    /* @dev Harvest and deposit LP tokens into the pool */
    function deposit(uint256 _pid, uint256 _amount) public nonReentrant {
        require(isActive,'Not active');
        _deposit(_pid,_amount,msg.sender,false);
    }

    function _deposit(uint256 _pid, uint256 _amount, address _addr, bool _isDirect) private {

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_addr];

        updatePool(_pid);

        if (user.amount > 0) {
            _harvest(_pid,_addr);
        } else {
            if (_amount > 0) {
                pool.totalStakers += pool.totalStakers+1; 
            }
        }

        if (_amount > 0) {

            if(!_isDirect){
                pool.lpToken.safeTransferFrom(address(_addr), address(this), _amount);
            }
            
            user.amount = user.amount + _amount;

        }

        if(user.firstStake == 0){
            // set the timestamp for the addresses first stake
            user.firstStake = block.timestamp;
        }

        user.rewardDebt = (user.amount * pool.accRewardsPerShare)/1e12;
        emit Deposit(_addr, _pid, _amount);
    }

   

    /* @dev Harvest and withdraw LP tokens from a pool*/
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        require(isActive,'Not active');

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        require(user.amount >= _amount && _amount > 0, "withdraw: no tokens to withdraw");
        updatePool(_pid);
        _harvest(_pid,msg.sender);

        if (_amount > 0) {
            user.amount = user.amount - _amount;

            // check and charge the withdraw fee
            uint256 withdrawFeePercent = _currentFeePercent(msg.sender, _pid);

            uint256 withdrawFee = (_amount * withdrawFeePercent)/10000;

            // subtract the fee from the amount we send
            uint256 toSend = _amount - withdrawFee;

            // transfer the fee
            pool.lpToken.safeTransfer(feeAddress, withdrawFee);
      
            // transfer to user 
            pool.lpToken.safeTransfer(address(msg.sender), toSend);
        }

        if(user.amount == 0){
            // decrement the total stakers
            pool.totalStakers = pool.totalStakers-1; 

            // reset this users first stake
            user.firstStake = 0;
        }
        user.rewardDebt = (user.amount * pool.accRewardsPerShare)/1e12;
        emit Withdraw(msg.sender, _pid, _amount);
    }

    /* @dev Withdraw entire balance without caring about rewards. EMERGENCY ONLY */
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
            
        // check and charge the withdraw fee
        uint256 withdrawFeePercent = _currentFeePercent(msg.sender, _pid);
        uint256 withdrawFee = (amount * withdrawFeePercent)/10000;

        // subtract the fee from the amount we send
        uint256 toSend = amount - withdrawFee;

        // transfer the fee
        pool.lpToken.safeTransfer(feeAddress, withdrawFee);
  
        // transfer to user 
        pool.lpToken.safeTransfer(address(msg.sender), toSend);

        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    /* @dev Return the current fee */
    function currentFeePercent (address _addr, uint256 _pid) external view returns(uint256){
        return _currentFeePercent(_addr, _pid);
    }

    /* @dev calculate the current fee based on first stake and current timestamp */
    function _currentFeePercent (address _addr, uint256 _pid) internal view returns(uint256){
        // get the time they staked
        uint256 startTime = userInfo[_pid][_addr].firstStake;

        // get the current time
        uint256 currentTime = block.timestamp;

        // check the times
        for (uint256 i = 0; i < feeInfo.length; ++i) {
            uint256 t = startTime + feeInfo[i].timeCheck;
            if(currentTime < t){
                return feeInfo[i].feePercent;
            }
        }

        return defaultFeePercent;
    }

    event LPAddedDirect(address indexed user, uint256 indexed pid, uint directStake, uint256 amoutNativeSent, uint256 amountTokenPost, uint256 amountNativePost, uint256 amountLPPost);
    /* @dev send in any amount of Native to have it paired to LP and auto-staked */
    function directToLp(uint256 _pid) public payable nonReentrant {
        require(isActive,'Not active');
        require(poolInfo[_pid].directStake > 0 ,'No direct stake');
        require(!isSwapping,'Token swap in progress');
        require(!isAddingLp,'Add LP in progress');
        require(msg.value >= minPairAmount, "Not enough Native to swap");

        uint256 liquidity;
        uint256 _amountToken;
        uint256 _amountNative;
        uint256 _amountLP;

        // directStake 1 - stake only the token (use the LPaddress)
        if(poolInfo[_pid].directStake == 1){
            // get the current token balance
            uint256 sasContractTokenBal = poolInfo[_pid].lpToken.balanceOf(address(this));
            _swapNativeForToken(msg.value, address(poolInfo[_pid].lpToken));
            liquidity = poolInfo[_pid].lpToken.balanceOf(address(this)) - sasContractTokenBal;
            _amountToken = liquidity;
        }

        // directStake 2 - pair Native/tokenA 
        if(poolInfo[_pid].directStake == 2){
            // use half the Native to buy the token
            uint256 nativeToSpend = msg.value/2;
            uint256 nativeToPost =  msg.value - nativeToSpend;

            // get the current token balance
            uint256 contractTokenBal = poolInfo[_pid].tokenA.balanceOf(address(this));
           
            // do the swap
            _swapNativeForToken(nativeToSpend, address(poolInfo[_pid].tokenA));

            //new balance
            uint256 tokenToPost = poolInfo[_pid].tokenA.balanceOf(address(this)) - contractTokenBal;

            // add LP
            (,, uint lp) = _addLiquidity(address(poolInfo[_pid].tokenA),tokenToPost, nativeToPost);
            liquidity = lp;

            _amountToken = tokenToPost;
            _amountNative = nativeToPost;
            _amountLP = lp;
        }

        // directStake 3 - pair tokenA/tokenB
        if(poolInfo[_pid].directStake == 3){

            // split the Native
            // use half the Native to buy the tokens
            uint256 nativeForTokenA = msg.value/2;
            uint256 nativeForTokenB =  msg.value - nativeForTokenA;

            // get the current token balances
            uint256 contractTokenABal = poolInfo[_pid].tokenA.balanceOf(address(this));
            uint256 contractTokenBBal = poolInfo[_pid].tokenB.balanceOf(address(this));

            // buy both tokens
            _swapNativeForToken(nativeForTokenA, address(poolInfo[_pid].tokenA));
            _swapNativeForToken(nativeForTokenB, address(poolInfo[_pid].tokenB));

            // get the balance to post
            uint256 tokenAToPost = poolInfo[_pid].tokenA.balanceOf(address(this)) - contractTokenABal;
            uint256 tokenBToPost = poolInfo[_pid].tokenB.balanceOf(address(this)) - contractTokenBBal;

            // pair it
            (,, uint lp) =  _addLiquidityTokens( 
                address(poolInfo[_pid].tokenA), 
                address(poolInfo[_pid].tokenB), 
                tokenAToPost, 
                tokenBToPost
            );
            liquidity = lp;

            _amountToken = tokenAToPost;
            _amountNative = tokenBToPost;
            _amountLP = lp;

        }
        
        emit LPAddedDirect(msg.sender,_pid,poolInfo[_pid].directStake, msg.value,_amountToken, _amountNative, _amountLP);

        // stake it to the contract
        _deposit(_pid,liquidity,msg.sender,true);

    }


    // LP Functions
    // adds liquidity and send it to the contract
    function _addLiquidity(address token, uint256 tokenamount, uint256 nativeamount) private returns(uint, uint, uint){
        isAddingLp = true;
        uint amountToken;
        uint amountETH;
        uint liquidity;

       (amountToken, amountETH, liquidity) = pancakeRouter.addLiquidityETH{value: nativeamount}(
            address(token),
            tokenamount,
            0,
            0,
            address(this),
            block.timestamp
        );
        isAddingLp = false;
        return (amountToken, amountETH, liquidity);

    }

    function _addLiquidityTokens(address _tokenA, address _tokenB, uint256 _tokenAmountA, uint256 _tokenAmountB) private returns(uint, uint, uint){
        isAddingLp = true;
        uint amountTokenA;
        uint amountTokenB;
        uint liquidity;

       (amountTokenA, amountTokenB, liquidity) = pancakeRouter.addLiquidity(
            address(_tokenA),
            address(_tokenB),
            _tokenAmountA,
            _tokenAmountB,
            0,
            0,
            address(this),
            block.timestamp
        );
        isAddingLp = false;

        return (amountTokenA, amountTokenB, liquidity);

    }

    function _swapNativeForToken(uint256 amount, address _token) private {
        isSwapping = true;
        address[] memory path = new address[](2);
        path[0] = pancakeRouter.WETH();
        path[1] = address(_token);

        pancakeRouter.swapExactETHForTokensSupportingFeeOnTransferTokens{value: amount}(
            0,
            path,
            address(this),
            block.timestamp
        );
        isSwapping = false;
    }

    function _swapTokenForToken(address _tokenA, address _tokenB, uint256 _amount) private {
        isSwapping = true;
        address[] memory path = new address[](2);
        path[0] = address(_tokenA);
        path[1] = address(_tokenB);

        pancakeRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amount,
            0,
            path,
            address(this),
            block.timestamp
        );
        isSwapping = false;
    }

    /* @dev Safe token transfer function, just in case if rounding error causes pool to not have enough tokens */
    function safeTokenTransfer(address _to, uint256 _amount) internal {
        uint256 bal = rewardToken.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > bal) {
            transferSuccess = rewardToken.transfer(_to, bal);
        } else {
            transferSuccess = rewardToken.transfer(_to, _amount);
        }
        require(transferSuccess, "safeTokenTransfer: transfer failed");
    }

    function setActive(bool _isActive) public onlyOwner {
        isActive = _isActive;
        emit SetActive(_isActive);
    }

    event MinPairAmountSet(uint256 minPairAmount);
    function setMinPairAmount(uint256 _minPairAmount) public onlyOwner {
        minPairAmount = _minPairAmount;
        emit MinPairAmountSet(_minPairAmount);
    }

    event DefaultFeeSet(uint256 fee);
    function setDefaultFee(uint256 _defaultFeePercent) public onlyOwner {
        require(_defaultFeePercent <= 500, "fee too high");
        defaultFeePercent = _defaultFeePercent;
        emit DefaultFeeSet(_defaultFeePercent);
    }


    function updateTokenContract(IERC20Minter _rewardToken) public onlyOwner {
        rewardToken = _rewardToken;
        rewardToken.approve(address(pancakeRouter), type(uint256).max);
    }

    function setFeeAddress(address _feeAddress) public {
        require(_feeAddress != address(0),'Invalid Address');
        require(msg.sender == feeAddress, "setFeeAddress: FORBIDDEN");
        feeAddress = _feeAddress;
        emit SetFeeAddress(msg.sender, _feeAddress);
    }

    function updateEmissionRate(uint256 _rewardsPerBlock) public onlyOwner {
        massUpdatePools();
        rewardsPerBlock = _rewardsPerBlock;
        emit UpdateEmissionRate(msg.sender, _rewardsPerBlock);
    }

    /**
     * @dev Update the LpStaking contract address only callable by the owner
     */
    function setNftRewardsContract(INftRewards _nftRewardsContract) public onlyOwner {
        nftRewardsContract = _nftRewardsContract;
    }

    // pull all the tokens out of the contract, needed for migrations/emergencies 
    function withdrawToken() public onlyOwner {
        safeTokenTransfer(feeAddress, rewardToken.balanceOf(address(this)));
    }

    // pull all the native out of the contract, needed for migrations/emergencies 
    function withdrawNative() public onlyOwner {
         (bool sent,) =address(feeAddress).call{value: (address(this).balance)}("");
        require(sent,"withdraw failed");
    }


    receive() external payable {}
}
