// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./SafeMath.sol";
import "./IERC165.sol";
import "./ReentrancyGuard.sol";
import "./SafeERC20.sol";
import "./IERC721.sol";
import "./IERC721Enumerable.sol";
import "./Operator.sol";

interface IReferral {
    /**
     * @dev record referrer address.
     */
    function recordReferral(address user, address _referrer) external;
    /**
     * @dev Get the referrer address that referred the user.
     */
    function getReferrer(address user) external view returns (address);
}

interface ILKEY {
    /**
     * @dev Get NFT Price in Token.
     */
    function getNFTPriceInToken(address _token) external view returns (uint256);
}

contract GenesisRewardPool is Operator, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many tokens the user has provided.
        uint256 boostedAmount; // How many boosted tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    // NFT Info of each user 
    struct NftUserInfo {
        uint256 nftAmount;  // How many nft tokens the user has provided.
        uint256[] nftTokenIds; // Staked nft token Ids
        uint256 stakedTS;   // Staked nft timestamp
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 token; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. PETH to distribute.
        uint256 lastRewardTime; // Last time that PETH distribution occurs.
        uint256 accPETHPerShare; // Accumulated PETH per share, times 1e18. See below.
        bool isStarted; // if lastRewardBlock has passed
        uint256 depositFee; // deposit fee
        uint256 tokenType; // 0 stable token, 1 partnership token, 2 lp
        uint256 boostedSupply; // How many boosted tokens supply.
    }

    // Info of invest 
    struct InvestInfo {
        uint256 totalInvested;
        uint256 investedTS;
    }

    IERC20 public PETH;

    IERC721Enumerable public nftToken;

    IReferral public referral;

    // Info of each pool.
    PoolInfo[] public poolInfo;

    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    // Info of each user that stakes NFT tokens.
    mapping(uint256 => mapping(address => NftUserInfo)) public nftUserInfo;

    mapping(uint256 => InvestInfo) public investInfo;

    // Info of total invested for NFT discount
    uint256[] public totalInvested;

    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;

    // Fee collector address
    address public feeCollector;

    // The time when PETH mining starts.
    uint256 public poolStartTime;

    // The time when PETH mining ends.
    uint256 public poolEndTime;

    uint256 public PETHPerSecond = 0.005 ether; // 3024 PETH / (7 days * 24h * 3600s)
    uint256 public constant RUNNING_TIME = 7 days; // 7 days
    uint256 public constant NFT_LOCKS = 15 days;
    uint256 public constant INVEST_LOCKS = 30 days;
    uint256 public constant TOTAL_REWARDS = 3024 ether;
    uint256 public constant DISCOUNT_RATE = 2000;
    uint256 public constant REFERRAL_COMMISSION_RATE = 3000;
    uint256[] public KBOOSTS = [0, 300, 550, 750, 900, 1000];
    uint256 public constant DENOMINATOR = 10000;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event RewardPaid(address indexed user, uint256 amount);

    constructor(address _PETH, address _nftToken, address _referral, uint256 _poolStartTime, address _feeCollector) {
        require(block.timestamp < _poolStartTime, "late");
        require(_PETH != address(0), "PETH should be non-zero address");
        require(_feeCollector != address(0), "Fee Collector should be non-zero address");

        PETH = IERC20(_PETH);
        nftToken = IERC721Enumerable(_nftToken);
        referral = IReferral(_referral);
        feeCollector = _feeCollector;
        poolStartTime = _poolStartTime;
        poolEndTime = poolStartTime + RUNNING_TIME;
    }

    function checkPoolDuplicate(IERC20 _token) internal view {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            require(poolInfo[pid].token != _token, "This pool already exist");
        }
    }

    // Add a new token to the pool. Can only be called by the owner.
    function add(
        uint256 _allocPoint,
        IERC20 _token,
        uint256 _depositFee,
        bool _withUpdate,
        uint256 _lastRewardTime,
        uint256 _tokenType
    ) public onlyOwner {
        checkPoolDuplicate(_token);
        if (_withUpdate) {
            massUpdatePools();
        }
        if (block.timestamp < poolStartTime) {
            // chef is sleeping
            if (_lastRewardTime == 0) {
                _lastRewardTime = poolStartTime;
            } else {
                if (_lastRewardTime < poolStartTime) {
                    _lastRewardTime = poolStartTime;
                }
            }
        } else {
            // chef is cooking
            if (_lastRewardTime == 0 || _lastRewardTime < block.timestamp) {
                _lastRewardTime = block.timestamp;
            }
        }
        bool _isStarted = (_lastRewardTime <= poolStartTime) || (_lastRewardTime <= block.timestamp);
        poolInfo.push(
            PoolInfo({
                token: _token, 
                tokenType: _tokenType,
                allocPoint: _allocPoint, 
                depositFee: _depositFee,
                lastRewardTime: _lastRewardTime, 
                accPETHPerShare: 0, 
                boostedSupply: 0,
                isStarted: _isStarted}));
        if (_isStarted) {
            totalAllocPoint = totalAllocPoint.add(_allocPoint);
        }
    }

    // Update the given pool's PETH allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint256 _depositFee) public onlyOwner {
        require(_depositFee < 10000, "deposit fee should be less than 10000");

        massUpdatePools();
        PoolInfo storage pool = poolInfo[_pid];
        if (pool.isStarted) {
            totalAllocPoint = totalAllocPoint.sub(pool.allocPoint).add(_allocPoint);
        }
        pool.allocPoint = _allocPoint;
        pool.depositFee = _depositFee;
    }

    // Set Fee Collector address
    function setFeeCollector(address _feeCollector) public onlyOwner {
        require(_feeCollector != address(0), "Fee collector should be non-zero address");
        feeCollector = _feeCollector;
    }

    function investAssets(uint256 _pid, uint256 _amount) public onlyOperator {
        require(_pid < poolInfo.length, "Invalid pool Id");
        PoolInfo storage pool = poolInfo[_pid];
        IERC20(pool.token).safeTransferFrom(msg.sender, address(this), _amount);
        investInfo[_pid].totalInvested = investInfo[_pid].totalInvested.add(_amount);
        investInfo[_pid].investedTS = block.timestamp;
    }

    // Return accumulate rewards over the given _from to _to block.
    function getGeneratedReward(uint256 _fromTime, uint256 _toTime) public view returns (uint256) {
        if (_fromTime >= _toTime) return 0;
        if (_toTime >= poolEndTime) {
            if (_fromTime >= poolEndTime) return 0;
            if (_fromTime <= poolStartTime) return poolEndTime.sub(poolStartTime).mul(PETHPerSecond);
            return poolEndTime.sub(_fromTime).mul(PETHPerSecond);
        } else {
            if (_toTime <= poolStartTime) return 0;
            if (_fromTime <= poolStartTime) return _toTime.sub(poolStartTime).mul(PETHPerSecond);
            return _toTime.sub(_fromTime).mul(PETHPerSecond);
        }
    }

    // View function to see pending PETH on frontend.
    function pendingPETH(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        uint256 accPETHPerShare = pool.accPETHPerShare;
        // uint256 tokenSupply = pool.token.balanceOf(address(this));
        uint256 boostedTokenSupply = pool.boostedSupply;
        if (block.timestamp > pool.lastRewardTime && boostedTokenSupply != 0) {
            uint256 _generatedReward = getGeneratedReward(pool.lastRewardTime, block.timestamp);
            uint256 _PETHReward = _generatedReward.mul(pool.allocPoint).div(totalAllocPoint);
            accPETHPerShare = accPETHPerShare.add(_PETHReward.mul(1e18).div(boostedTokenSupply));
        }
        uint256 boostedUserAmount = user.boostedAmount;
        return boostedUserAmount.mul(accPETHPerShare).div(1e18).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }
        // uint256 tokenSupply = pool.token.balanceOf(address(this));
        uint256 boostedTokenSupply = pool.boostedSupply;
        if (boostedTokenSupply == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        if (!pool.isStarted) {
            pool.isStarted = true;
            totalAllocPoint = totalAllocPoint.add(pool.allocPoint);
        }
        if (totalAllocPoint > 0) {
            uint256 _generatedReward = getGeneratedReward(pool.lastRewardTime, block.timestamp);
            uint256 _PETHReward = _generatedReward.mul(pool.allocPoint).div(totalAllocPoint);
            pool.accPETHPerShare = pool.accPETHPerShare.add(_PETHReward.mul(1e18).div(boostedTokenSupply));
        }
        pool.lastRewardTime = block.timestamp;
    }

    // Deposit tokens.
    function deposit(uint256 _pid, uint256 _amount, address _referrer) public {
        address _sender = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_sender];
        updatePool(_pid);
        if (_amount > 0 && address(referral) != address(0) && _referrer != address(0) && _referrer != msg.sender) {
            referral.recordReferral(msg.sender, _referrer);
        }
        uint256 kBoost = getKBoost(_pid, msg.sender);
        if (user.amount > 0) {
            uint256 boostedUserAmount = user.boostedAmount;
            uint256 _pending = boostedUserAmount.mul(pool.accPETHPerShare).div(1e18).sub(user.rewardDebt);
            if (_pending > 0) {
                safePETHTransfer(_sender, _pending);
                emit RewardPaid(_sender, _pending);
            }
        }
        if (_amount > 0) {
            pool.token.safeTransferFrom(_sender, address(this), _amount);
            uint256 _boostingAmount = (_amount).mul(DENOMINATOR.add(kBoost)).div(DENOMINATOR);
            user.amount = user.amount.add(_amount);
            user.boostedAmount = user.boostedAmount.add(_boostingAmount);
            if (pool.depositFee > 0) {
                uint256 feeAmount = _amount.mul(pool.depositFee).div(DENOMINATOR);
                uint256 referralCommissionAmount = 0;
                if(_referrer != address(0) && _referrer != msg.sender) {
                    referralCommissionAmount = feeAmount.mul(REFERRAL_COMMISSION_RATE).div(DENOMINATOR);
                    payReferralCommission(_sender, pool.token, referralCommissionAmount);
                }
                pool.token.safeTransfer(feeCollector, feeAmount.sub(referralCommissionAmount));
                user.amount = user.amount.sub(feeAmount);
            } 
            pool.boostedSupply = pool.boostedSupply.add(_boostingAmount);
        }
        user.rewardDebt = user.boostedAmount.mul(pool.accPETHPerShare).div(1e18);
        emit Deposit(_sender, _pid, _amount);
    }

    // Withdraw LP tokens.
    function withdraw(uint256 _pid, uint256 _amount) public {
        address _sender = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_sender];

        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 kBoost = getKBoost(_pid, msg.sender);
        uint256 _pending = user.boostedAmount.mul(pool.accPETHPerShare).div(1e18).sub(user.rewardDebt);
        if (_pending > 0) {
            safePETHTransfer(_sender, _pending);
            emit RewardPaid(_sender, _pending);
        }
        if (_amount > 0) {
            uint256 _boostingAmount = (_amount).mul(DENOMINATOR.add(kBoost)).div(DENOMINATOR);
            user.amount = user.amount.sub(_amount);
            user.boostedAmount = user.boostedAmount.sub(_boostingAmount);
            pool.boostedSupply = pool.boostedSupply.sub(_boostingAmount);
            pool.token.safeTransfer(_sender, _amount);
        }
        user.rewardDebt = user.boostedAmount.mul(pool.accPETHPerShare).div(1e18);
        emit Withdraw(_sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 _amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.boostedSupply = pool.boostedSupply.sub(user.boostedAmount);
        pool.token.safeTransfer(msg.sender, _amount);
        emit EmergencyWithdraw(msg.sender, _pid, _amount);
    }

    // Stake NFT tokens
    function stakeNFT(uint256 _pid, uint256 _nftCount) public {
        require(_pid < poolInfo.length, "Invalid pool id");
        require(_nftCount > 0, "NFT count should be greater than 0");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        NftUserInfo storage nftUser = nftUserInfo[_pid][msg.sender];
        updatePool(_pid);

        uint256 poolTokenType = pool.tokenType;
        require(poolTokenType < 2, "NFTs can't be staked into the LP token pool");

        uint256 nftBalance = nftToken.balanceOf(msg.sender);
        require(nftBalance >= _nftCount, "NFT balance shold be greater than count");
        
        for(uint256 i = 0; i < _nftCount; i++) {
            uint256 tokenId = nftToken.tokenOfOwnerByIndex(msg.sender, i);
            nftToken.transferFrom(msg.sender, address(this), tokenId);
            nftUser.nftTokenIds.push(tokenId);
        }
        nftUser.nftAmount = nftUser.nftAmount.add(_nftCount);
        nftUser.stakedTS = block.timestamp;
        uint256 kBoost = getKBoost(_pid, msg.sender);
        uint256 nftPrice = ILKEY(address(nftToken)).getNFTPriceInToken(address(pool.token));
        uint256 _nftDiscountValue = nftPrice.mul(_nftCount).mul(DISCOUNT_RATE).div(DENOMINATOR);
        user.amount = user.amount.add(_nftDiscountValue);
        uint256 oldBoostedAmount = user.boostedAmount;
        user.boostedAmount = user.amount.mul(DENOMINATOR.add(kBoost)).div(DENOMINATOR);
        pool.boostedSupply = pool.boostedSupply.add(user.boostedAmount).sub(oldBoostedAmount); 

    }

    // Withdraw NFT tokens
    function unstakeNFT(uint256 _pid) public {
        NftUserInfo storage nftUser = nftUserInfo[_pid][msg.sender];
        uint256 nftStakedTS = nftUser.stakedTS;
        require(nftStakedTS + NFT_LOCKS >= block.timestamp, "Can stake after locks up from last staked time" );
        for (uint256 i = 0; i < nftUser.nftAmount; i++) {
            uint256 tokenId = nftUser.nftTokenIds[nftUser.nftAmount - i - 1];
            nftToken.transferFrom(address(this), msg.sender, tokenId);
            nftUser.nftTokenIds.pop();
        }
        nftUser.nftAmount = 0;
    }

    // Safe PETH transfer function, just in case if rounding error causes pool to not have enough PETHs.
    function safePETHTransfer(address _to, uint256 _amount) internal {
        uint256 _PETHBalance = PETH.balanceOf(address(this));
        if (_PETHBalance > 0) {
            if (_amount > _PETHBalance) {
                PETH.safeTransfer(_to, _PETHBalance);
            } else {
                PETH.safeTransfer(_to, _amount);
            }
        }
    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        if (block.timestamp < poolEndTime + 90 days) {
            // do not allow to drain core token (PETH or lps) if less than 90 days after pool ends
            require(_token != PETH, "Shouldn't drain PETH if less than 90 days after pool ends");
            uint256 length = poolInfo.length;
            for (uint256 pid = 0; pid < length; ++pid) {
                PoolInfo storage pool = poolInfo[pid];
                require(_token != pool.token, "Shouldn't drain staking token & LPs if less than 90 days after pool ends");
            }
        }
        _token.safeTransfer(_to, _amount);
    }

    // Pay referral commission to the referrer who referred this user.
    function payReferralCommission(address _user, IERC20 _poolToken, uint256 _commissionAmount) internal {
        if (address(referral) != address(0)) {
            address referrer = referral.getReferrer(_user);
            if (referrer != address(0) && _commissionAmount > 0) {
                _poolToken.safeTransfer(referrer, _commissionAmount);
            }
        }
    }

    function getKBoost(uint256 _pid, address _user) public view returns (uint256) {
        NftUserInfo storage nftUser = nftUserInfo[_pid][_user];
        uint256 nftAmount = nftUser.nftAmount;
        uint256 kBoost = 0;
        if(nftAmount >= KBOOSTS.length) {
            kBoost = KBOOSTS[KBOOSTS.length - 1];
        } else {
            kBoost = KBOOSTS[nftAmount];
        }
        return kBoost;
    }
    
}
