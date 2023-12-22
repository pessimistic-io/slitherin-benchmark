// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./SafeMath.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./IFeeLP.sol";
import "./EnumerableSet.sol";

interface ILionDexNFT {
    function genesisMaxTokenId() external view returns (uint256);

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    function getApproved(uint256 tokenId) external view returns (address);

    function isApprovedForAll(
        address owner,
        address operator
    ) external view returns (bool);

    function ownerOf(uint256 tokenId) external view returns (address);
}

interface ILionDEXRewardVault {
    function withdrawEth(uint256 amount) external;

    function withdrawToken(IERC20 token, uint256 amount) external;
}

contract BasePools is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 totalAmount; //deposit token's total amount
        uint256[] amount; //deposit token's amount
        uint256[] rewardDebt; //reward token's
        uint256 buff1;
        uint256 buff2;
        uint256 weight;
    }

    // Info of each pool.
    struct PoolInfo {
        uint256 startTime;
        IERC20[] depositTokens;
        IERC20[] rewardTokens;
        uint256[] rewardTokenPerSecond;
        uint256 lastRewardTime;
        uint256[] accRewardTokenPerShare;
        uint256[] staked; //total staked per token
        uint256 totalStaked; //sum deposit token's staked amount
        uint256 totalWeight;
    }

    uint256 public constant BasePoint = 1e4;
    uint256 public constant buffPerNFT = 500;
    uint256 public constant pfpBuffPerNFT = 200;
    uint256 public constant precise = 1e18;
    address public constant WETH =
        address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    PoolInfo[] public poolInfo;
    //poolId=>user=>user info
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    ILionDEXRewardVault public rewardVault;
    mapping(address => bool) public rewardKeeperMap;

    event Deposit(
        address indexed user,
        uint256 indexed pid,
        IERC20 depositToken,
        uint256 amount
    );
    event Withdraw(
        address indexed user,
        uint256 indexed pid,
        IERC20 withdrawToken,
        uint256 amount
    );
    event SetRewardKeeper(address sender,address addr,bool active);
    modifier onlyRewardKeeper() {
        require(isRewardKeeper(msg.sender), "StartPools: not keeper");
        _;
    }

    function init(ILionDEXRewardVault _rewardVault) internal {
        rewardVault = _rewardVault;
        rewardKeeperMap[msg.sender] = true;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function addPool(
        uint256 startTime,
        IERC20[] memory depositTokens,
        IERC20[] memory rewardTokens,
        uint256[] memory rewardTokenPerSecond
    ) public onlyOwner {
        require(startTime > block.timestamp, "BasePools: startTime invalid");

        require(
            depositTokens.length > 0 &&
                rewardTokens.length > 0 &&
                rewardTokens.length == rewardTokenPerSecond.length,
            "BasePools: invalid length"
        );
        poolInfo.push(
            PoolInfo(
                startTime,
                depositTokens,
                rewardTokens,
                rewardTokenPerSecond,
                startTime, //lastRewardTime
                new uint256[](rewardTokens.length), //accRewardTokenPerShare
                new uint256[](depositTokens.length), //staked
                0, //totalStaked
                0
            )
        );
    }

    function setRewardTokenPerSecond(
        uint256 _pid,
        uint256[] memory rewardTokenPerSecond
    ) public onlyRewardKeeper {
        PoolInfo storage pi = poolInfo[_pid];
        require(pi.startTime > 0, "BasePools: not exists");
        require(
            pi.rewardTokens.length == rewardTokenPerSecond.length,
            "BasePools: length invalid"
        );
        updatePool(_pid);
        pi.rewardTokenPerSecond = rewardTokenPerSecond;
    }

    function pendingReward(
        uint256 _pid,
        address _user
    ) external view returns (uint256[] memory rewards) {
        require(_pid < poolInfo.length, "BasePools: pid not exists");

        PoolInfo memory pool = poolInfo[_pid];
        UserInfo memory user = userInfo[_pid][_user];
        if (pool.totalWeight == 0 || user.weight == 0) {
            return rewards;
        }
        uint256 tokenLength = pool.rewardTokens.length;
        rewards = new uint256[](tokenLength);

        for (uint i; i < tokenLength; i++) {
            uint256 multipier = getMultiplier(
                pool.lastRewardTime,
                block.timestamp
            );
            uint256 reward = multipier.mul(pool.rewardTokenPerSecond[i]);
            uint256 accRewardPerShare = pool.accRewardTokenPerShare[i].add(
                reward.mul(precise).div(pool.totalWeight)
            );
            uint256 current = user.weight.mul(accRewardPerShare).div(precise);
            if (current <= user.rewardDebt[i]) {
                continue;
            }
            rewards[i] = current.sub(user.rewardDebt[i]);
        }
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
        if (pool.startTime == 0) {
            return;
        }
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }
        if (pool.totalWeight == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        uint256 tokenLength = pool.rewardTokens.length;
        for (uint i; i < tokenLength; i++) {
            uint256 multiplier = getMultiplier(
                pool.lastRewardTime,
                block.timestamp
            );
            uint256 reward = multiplier.mul(pool.rewardTokenPerSecond[i]);

            pool.accRewardTokenPerShare[i] = pool.accRewardTokenPerShare[i].add(
                reward.mul(precise).div(pool.totalWeight)
            );
        }
        pool.lastRewardTime = block.timestamp;
    }

    // Deposit tokens to specific pool for reward
    function deposit(
        uint256 _pid,
        IERC20 depositToken,
        uint256 _amount
    ) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        require(pool.startTime > 0, "BasePools: pool not exist");
        require(
            checkPoolToken(_pid, depositToken),
            "BasePools: deposit token invalid"
        );
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount.length == 0) {
            user.amount = new uint256[](pool.depositTokens.length);
        }
        if (user.rewardDebt.length == 0) {
            user.rewardDebt = new uint256[](pool.rewardTokens.length);
        }

        //transfer pending reward
        if (user.weight > 0) {
           transferRewards(pool, user);
        }

        if (_amount > 0) {
            depositToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
            for (uint i; i < pool.depositTokens.length; i++) {
                if (pool.depositTokens[i] == depositToken) {
                    user.amount[i] = user.amount[i].add(_amount);
                    pool.staked[i] = pool.staked[i].add(_amount);
                }
            }
            user.totalAmount = user.totalAmount.add(_amount);
            pool.totalStaked = pool.totalStaked.add(_amount);
            //110/100
            uint256 buff = _amount.mul(user.buff1 + user.buff2 + BasePoint).div(
                BasePoint
            );
            user.weight = user.weight.add(buff);

            pool.totalWeight = pool.totalWeight.add(buff);
        }

        updateRewardDebt(pool, user);

        emit Deposit(msg.sender, _pid, depositToken, _amount);
    }

    function withdraw(
        uint256 _pid,
        IERC20 withdrawToken,
        uint256 _amount
    ) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        require(pool.startTime > 0, "BasePools: pool not exist");
        require(
            checkPoolToken(_pid, withdrawToken),
            "BasePools: withdraw token invalid"
        );
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);

        //transfer pending reward
        if (user.weight > 0) {
           transferRewards(pool, user);
        }

        if (_amount > 0) {
            for (uint i; i < pool.depositTokens.length; i++) {
                if (pool.depositTokens[i] == withdrawToken) {
                    require(
                        user.amount[i] >= _amount,
                        "BasePools: _amount invalid"
                    );
                    user.amount[i] = user.amount[i].sub(_amount);
                    pool.staked[i] = pool.staked[i].sub(_amount);
                }
            }

            user.totalAmount = user.totalAmount.sub(_amount);
            pool.totalStaked = pool.totalStaked.sub(_amount);
            uint256 buff = _amount.mul(user.buff1 + user.buff2 + BasePoint).div(
                BasePoint
            );
            user.weight = user.weight.sub(buff);
            pool.totalWeight = pool.totalWeight.sub(buff);

            withdrawToken.safeTransfer(address(msg.sender), _amount);
        }

        updateRewardDebt(pool, user);

        emit Withdraw(msg.sender, _pid, withdrawToken, _amount);
    }

    function updateRewardDebt(
        PoolInfo storage pool,
        UserInfo storage user
    ) private {
        for (uint i; i < pool.rewardTokens.length; i++) {
            user.rewardDebt[i] = user
                .weight
                .mul(pool.accRewardTokenPerShare[i])
                .div(precise);
        }
    }

    function transferRewards(
        PoolInfo storage pool,
        UserInfo storage user
    ) private {
        uint256 tokenLength = pool.rewardTokens.length;
        for (uint i; i < tokenLength; i++) {
                uint256 current = user
                    .weight
                    .mul(pool.accRewardTokenPerShare[i])
                    .div(precise);
                if (current <= user.rewardDebt[i]) {
                    continue;
                }
                uint256 pending = current.sub(user.rewardDebt[i]);
                if (pending > 0) {
                    if (address(pool.rewardTokens[i]) == address(0)) {
                        //Reward: ETH
                        rewardVault.withdrawEth(pending);
                        require(
                            payable(msg.sender).send(pending),
                            "BasePools: send eth false"
                        );
                    } else {
                        rewardVault.withdrawToken(
                            pool.rewardTokens[i],
                            pending
                        );
                        pool.rewardTokens[i].safeTransfer(msg.sender, pending);
                    }
                }
        }
    }

    function checkPoolToken(
        uint256 pid,
        IERC20 token
    ) public view returns (bool) {
        uint256 depositTokenLength = poolInfo[pid].depositTokens.length;
        for (uint i; i < depositTokenLength; i++) {
            if (poolInfo[pid].depositTokens[i] == token) {
                return true;
            }
        }
        return false;
    }

    function getMultiplier(
        uint256 _from,
        uint256 _to
    ) public pure returns (uint256) {
        return _to.sub(_from);
    }

    function _addBuff(address user, uint256 newBuff, uint256 buffNum) internal {
        require(buffNum == 0 || buffNum == 1, "BasePools: Wrong Buff Num");
        //judger user buff
        for (uint i; i < poolInfo.length; i++) {
            UserInfo storage ui = userInfo[i][user];
            uint256 userBuffBefore = ui.buff1 + ui.buff2;
            if (buffNum == 0) {
                if (ui.buff1.add(newBuff) < buffPerNFT.mul(2)) {
                    ui.buff1 = ui.buff1.add(newBuff);
                } else {
                    ui.buff1 = buffPerNFT.mul(2);
                }
            } else {
                if (ui.buff2.add(newBuff) < pfpBuffPerNFT.mul(2)) {
                    ui.buff2 = ui.buff2.add(newBuff);
                } else {
                    ui.buff2 = pfpBuffPerNFT.mul(2);
                }
            }
            //judge update
            if (userBuffBefore != (ui.buff1 + ui.buff2) && ui.totalAmount > 0) {
                deposit(i, poolInfo[i].depositTokens[0], 0);
                uint256 weightBefore = ui.weight;
                ui.weight = ui
                    .totalAmount
                    .mul(ui.buff1 + ui.buff2 + BasePoint)
                    .div(BasePoint);
                poolInfo[i].totalWeight = poolInfo[i]
                    .totalWeight
                    .sub(weightBefore)
                    .add(ui.weight);
                updateRewardDebt(poolInfo[i], ui);
            }
        }
    }

    function _updateBuff(
        address user,
        uint256 leftBuff,
        uint256 buffNum
    ) internal {
        require(buffNum == 0 || buffNum == 1, "BasePools:Wrong Buff Num");
        if ((buffNum == 0) && (leftBuff >= buffPerNFT.mul(2))) {
            return;
        }
        if ((buffNum == 1) && (leftBuff >= pfpBuffPerNFT.mul(2))) {
            return;
        }
        for (uint i; i < poolInfo.length; i++) {
            UserInfo storage ui = userInfo[i][user];
            uint256 userBuffBefore = ui.buff1 + ui.buff2;
            if (buffNum == 0) {
                ui.buff1 = leftBuff;
            } else {
                ui.buff2 = leftBuff;
            }

            //judge update
            if (userBuffBefore != (ui.buff1 + ui.buff2) && ui.totalAmount > 0) {
                deposit(i, poolInfo[i].depositTokens[0], 0);
                uint256 weightBefore = ui.weight;
                ui.weight = ui
                    .totalAmount
                    .mul(ui.buff1 + ui.buff2 + BasePoint)
                    .div(BasePoint);
                poolInfo[i].totalWeight = poolInfo[i]
                    .totalWeight
                    .sub(weightBefore)
                    .add(ui.weight);
                updateRewardDebt(poolInfo[i], ui);
            }
        }
    }

    function getPoolInfo(
        uint256 pid
    )
        public
        view
        returns (
            uint256 startTime,
            IERC20[] memory depositTokens,
            IERC20[] memory rewardTokens,
            uint256[] memory rewardTokenPerSecond,
            uint256 lastRewardTime,
            uint256[] memory accRewardTokenPerShare,
            uint256[] memory staked,
            uint256 totalStaked,
            uint256 totalWeight
        )
    {
        require(pid < poolInfo.length, "BasePools: invalid params");
        startTime = poolInfo[pid].startTime;
        depositTokens = poolInfo[pid].depositTokens;
        rewardTokens = poolInfo[pid].rewardTokens;
        rewardTokenPerSecond = poolInfo[pid].rewardTokenPerSecond;
        lastRewardTime = poolInfo[pid].lastRewardTime;
        accRewardTokenPerShare = poolInfo[pid].accRewardTokenPerShare;
        staked = poolInfo[pid].staked; //total staked per token
        totalStaked = poolInfo[pid].totalStaked; //sum deposit token's staked amount
        totalWeight = poolInfo[pid].totalWeight;
    }

    function getUserInfo(
        uint256 pid,
        address user
    )
        public
        view
        returns (
            uint256 totalAmount,
            uint256[] memory amount,
            uint256[] memory rewardDebt,
            uint256 buff1,
            uint256 buff2,
            uint256 weight
        )
    {
        totalAmount = userInfo[pid][user].totalAmount;
        amount = userInfo[pid][user].amount;
        rewardDebt = userInfo[pid][user].rewardDebt;
        buff1 = userInfo[pid][user].buff1;
        buff2 = userInfo[pid][user].buff2;
        weight = userInfo[pid][user].weight;
    }

    function getTotalStakedLP() public view returns (uint256) {
        if (poolInfo.length > 1) {
            return poolInfo[1].totalStaked;
        } else {
            return 0;
        }
    }

    function setLionDEXRewardVault(
        ILionDEXRewardVault _rewardVault
    ) public onlyOwner {
        rewardVault = _rewardVault;
    }

    function setRewardKeeper(address addr, bool active) public onlyOwner {
        rewardKeeperMap[addr] = active;
        emit SetRewardKeeper(msg.sender,addr,active);
    }
    function isRewardKeeper(address addr) public view returns (bool) {
        return rewardKeeperMap[addr];
    }
}

contract FlexiblePools is BasePools {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;

    IERC20 public LionToken;
    IERC20 public esLionToken;

    ILionDexNFT public lionDexNFT;
    ILionDexNFT public lionPFPNFT;
    IFeeLP public feeLP;
    //feeLP amount per card
    uint256 public feeLPAmountPerNFT = 1500e18;
    //lionDexNFT tokenId=>owner's address
    mapping(uint256 => address) public tokenOfOwner;
    //lionPFPNFT tokenId=>owner's address
    mapping(uint256 => address) public pfpNFTOfOwner;
    //user=>lionDexNFT tokenId set
    mapping(address => EnumerableSet.UintSet) private ownerTokens;
    mapping(address => EnumerableSet.UintSet) private ownerPFPTokens;

    //for release lion,50000 lion per genesis NFT
    uint256 public lionTokenAmountPerNFT = 50000e18;
    uint256 public duration = 180 days;
    struct LionTokenClaim {
        uint256 depositTime;
        uint256 claimed;
    }
    //token id=>lion token claim info
    mapping(uint256 => LionTokenClaim) private lionTokenClaimInfo;

    event DepositNFT(address user, uint256[] tokenIds, uint256 amount);
    event DepositPFPNFT(address user, uint256[] tokenIds);
    event WithdrawNFT(
        address user,
        uint256[] tokenIds,
        uint256 needReturnFeeLP,
        uint256 needReturnLionToken
    );
    event WithdrawPFPNFT(address user, uint256[] tokenIds);
    event ClaimLion(address user, uint256 amount);

    function initialize(
        IERC20 _LionToken,
        IERC20 _esLionToken,
        ILionDEXRewardVault _rewardVault,
        ILionDexNFT _lionDexNFT,
        ILionDexNFT _lionPFPNFT,
        IFeeLP _feeLP
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        init(_rewardVault);

        lionDexNFT = _lionDexNFT;
        lionPFPNFT = _lionPFPNFT;
        feeLP = _feeLP;
        LionToken = _LionToken;
        esLionToken = _esLionToken;
        feeLPAmountPerNFT = 1500e18;
        lionTokenAmountPerNFT = 50000e18;
        duration = 180 days;
    }

    function depositNFT(uint256[] memory tokenIds) public {
        require(tokenIds.length > 0, "FlexiblePools: length invalid");

        for (uint i; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            LionTokenClaim storage info = lionTokenClaimInfo[tokenId];
            require(info.depositTime == 0, "FlexiblePools: deposited");
            require(
                lionDexNFT.ownerOf(tokenId) == msg.sender,
                "FlexiblePools: owner invalid"
            );
            require(
                lionDexNFT.getApproved(tokenId) == address(this) ||
                    lionDexNFT.isApprovedForAll(msg.sender, address(this)),
                "FlexiblePools: approved invalid"
            );
            require(
                !ownerTokens[msg.sender].contains(tokenId),
                "FlexiblePools: tokenId invalid"
            );
            lionDexNFT.safeTransferFrom(msg.sender, address(this), tokenId);
            tokenOfOwner[tokenId] = msg.sender;
            ownerTokens[msg.sender].add(tokenId);
            info.depositTime = block.timestamp;
        }

        uint256 needMint = feeLPAmountPerNFT.mul(tokenIds.length);
        feeLP.mintTo(msg.sender, needMint);

        //add buff
        uint256 newBuff = buffPerNFT.mul(tokenIds.length);
        _addBuff(msg.sender, newBuff, 0);

        emit DepositNFT(msg.sender, tokenIds, needMint);
    }

    function depositPFPNFT(uint256[] memory tokenIds) public {
        require(
            ownerPFPTokens[msg.sender].length() + tokenIds.length < 3,
            "FlexiblePools: length invalid"
        );

        for (uint i; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(
                lionPFPNFT.ownerOf(tokenId) == msg.sender,
                "FlexiblePools: owner invalid"
            );
            require(
                lionPFPNFT.getApproved(tokenId) == address(this) ||
                    lionPFPNFT.isApprovedForAll(msg.sender, address(this)),
                "FlexiblePools: approved invalid"
            );
            require(
                !ownerPFPTokens[msg.sender].contains(tokenId),
                "FlexiblePools: tokenId invalid"
            );
            lionPFPNFT.safeTransferFrom(msg.sender, address(this), tokenId);
            pfpNFTOfOwner[tokenId] = msg.sender;
            ownerPFPTokens[msg.sender].add(tokenId);
        }

        //add buff
        uint256 newBuff = pfpBuffPerNFT.mul(tokenIds.length);
        _addBuff(msg.sender, newBuff, 1);

        emit DepositPFPNFT(msg.sender, tokenIds);
    }

    function withdrawNFT(uint256[] memory tokenIds) public {
        require(tokenIds.length > 0, "FlexiblePools: length invalid");
        uint256 needReturnLionToken;
        for (uint i; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(
                tokenOfOwner[tokenId] == msg.sender,
                "FlexiblePools: owner invalid"
            );
            require(
                ownerTokens[msg.sender].contains(tokenId),
                "FlexiblePools: tokenId invalid"
            );
            lionDexNFT.safeTransferFrom(address(this), msg.sender, tokenId);
            ownerTokens[msg.sender].remove(tokenId);
            delete tokenOfOwner[tokenId];

            //for lion token,only return claimed
            needReturnLionToken = needReturnLionToken.add(
                lionTokenClaimInfo[tokenId].claimed
            );
            delete lionTokenClaimInfo[tokenId];
        }

        //for feeLP
        uint256 needReturnFeeLP = feeLPAmountPerNFT.mul(tokenIds.length);
        require(
            feeLP.balanceOf(msg.sender) >= needReturnFeeLP,
            "FlexiblePools: feeLP balance invalid"
        );
        feeLP.burn(msg.sender, needReturnFeeLP);

        //for lionToken
        if (needReturnLionToken > 0) {
            require(
                LionToken.balanceOf(msg.sender) >= needReturnLionToken,
                "FlexiblePools: lion balance invalid"
            );
            require(
                LionToken.allowance(msg.sender, address(this)) >=
                    needReturnLionToken,
                "FlexiblePools: lion approved invalid"
            );

            LionToken.safeTransferFrom(
                msg.sender,
                address(rewardVault),
                needReturnLionToken
            );
        }

        //set to left buff
        uint256 leftBuff = buffPerNFT.mul(ownerTokens[msg.sender].length());
        _updateBuff(msg.sender, leftBuff, 0);

        emit WithdrawNFT(
            msg.sender,
            tokenIds,
            needReturnFeeLP,
            needReturnLionToken
        );
    }

    function withdrawPFPNFT(uint256[] memory tokenIds) public {
        require(tokenIds.length > 0, "FlexiblePools: length invalid");
        for (uint i; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(
                pfpNFTOfOwner[tokenId] == msg.sender,
                "FlexiblePools: owner invalid"
            );
            require(
                ownerPFPTokens[msg.sender].contains(tokenId),
                "FlexiblePools: tokenId invalid"
            );
            lionPFPNFT.safeTransferFrom(address(this), msg.sender, tokenId);
            ownerPFPTokens[msg.sender].remove(tokenId);
            delete pfpNFTOfOwner[tokenId];
        }

        //set to left buff
        uint256 leftBuff = pfpBuffPerNFT.mul(
            ownerPFPTokens[msg.sender].length()
        );
        _updateBuff(msg.sender, leftBuff, 1);

        emit WithdrawPFPNFT(msg.sender, tokenIds);
    }

    function claimLion() public {
        uint256 len = ownerTokens[msg.sender].length();
        uint256 total;
        for (uint i; i < len; i++) {
            uint256 tokenId = ownerTokens[msg.sender].at(i);
            LionTokenClaim storage info = lionTokenClaimInfo[tokenId];
            (uint256 canClaim, ) = getCanClaim(tokenId);
            info.claimed = info.claimed.add(canClaim);
            total = total.add(canClaim);
        }
        if (total > 0) {
            rewardVault.withdrawToken(LionToken, total);
            LionToken.transfer(msg.sender, total);
        }

        emit ClaimLion(msg.sender, total);
    }

    function claimLionIndex(uint256 fromIndex, uint256 toIndex) public {
        require(fromIndex < toIndex, "FlexiblePools: params invalid");

        uint256 len = ownerTokens[msg.sender].length();
        if (toIndex > len) {
            toIndex = len;
        }
        uint256 total;
        for (uint i = fromIndex; i < toIndex; i++) {
            uint256 tokenId = ownerTokens[msg.sender].at(i);
            LionTokenClaim storage info = lionTokenClaimInfo[tokenId];
            (uint256 canClaim, ) = getCanClaim(tokenId);
            info.claimed = info.claimed.add(canClaim);
            total = total.add(canClaim);
        }
        if (total > 0) {
            rewardVault.withdrawToken(LionToken, total);
            LionToken.transfer(msg.sender, total);
        }

        emit ClaimLion(msg.sender, total);
    }

    function getNeedReturn(
        address user,
        uint256[] memory tokenIds
    )
        public
        view
        returns (uint256 needReturnLionToken, uint256 needReturnFeeLP)
    {
        for (uint i; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(
                tokenOfOwner[tokenId] == user,
                "FlexiblePools: owner invalid"
            );
            require(
                ownerTokens[user].contains(tokenId),
                "FlexiblePools: tokenId invalid"
            );

            //for lion token,only return claimed
            needReturnLionToken = needReturnLionToken.add(
                lionTokenClaimInfo[tokenId].claimed
            );
        }

        //for feeLP
        needReturnFeeLP = feeLPAmountPerNFT.mul(tokenIds.length);
    }

    function getCanClaim(
        address user
    ) private view returns (uint256 canClaim, uint256 claimed) {
        uint256 len = ownerTokens[user].length();
        for (uint i; i < len; i++) {
            uint256 tokenId = ownerTokens[user].at(i);
            (uint256 canClaimIn, uint256 claimedIn) = getCanClaim(tokenId);
            canClaim = canClaim.add(canClaimIn);
            claimed = claimed.add(claimedIn);
        }
    }

    function getCanClaim(
        uint256 tokenId
    ) private view returns (uint256, uint256) {
        LionTokenClaim memory info = lionTokenClaimInfo[tokenId];
        uint256 start = info.depositTime;
        uint256 claimed = info.claimed;
        if (block.timestamp <= start) {
            return (0, claimed);
        } else if (block.timestamp >= start.add(duration)) {
            return (lionTokenAmountPerNFT.sub(claimed), claimed);
        } else {
            return (
                lionTokenAmountPerNFT
                    .mul(block.timestamp.sub(start))
                    .div(duration)
                    .sub(claimed),
                claimed
            );
        }
    }

    function getOwnerTokens(
        address user
    ) external view returns (uint256[] memory ret) {
        ret = new uint256[](ownerTokens[user].length());
        for (uint i = 0; i < ownerTokens[user].length(); i++) {
            ret[i] = ownerTokens[user].at(i);
        }
    }

    function getOwnerFeeLP(address user) external view returns (uint256 ret) {
        ret = ownerTokens[user].length().mul(feeLPAmountPerNFT);
    }

    function getOwnerPFPTokens(
        address user
    ) external view returns (uint256[] memory ret) {
        ret = new uint256[](ownerPFPTokens[user].length());
        for (uint i = 0; i < ownerPFPTokens[user].length(); i++) {
            ret[i] = ownerPFPTokens[user].at(i);
        }
    }

    //user's lion token claim info
    function getUserClaimLionInfo(
        address user
    ) external view returns (uint256 total, uint256 canClaim, uint256 claimed) {
        uint256 len = ownerTokens[user].length();
        total = len.mul(lionTokenAmountPerNFT);
        (canClaim, claimed) = getCanClaim(user);
    }

    function getUserApr(
        uint256 pid,
        uint256 LPPrice,
        uint256 esLionPrice,
        uint256 ethPrice,
        address user
    ) public view returns (uint256[3] memory ret) {
        require(pid < 2, "BasePools: pid invalid");
        require(
            LPPrice > 0 && esLionPrice > 0 && ethPrice > 0,
            "BasePools: price invalid"
        );
        // (rewardTokenPerSecond*second per year *reward token usd price)*(1+((Genesis Amount*0.05)+(PFP Amount*0.02))) / (total staked token+buff) usd value
        uint256 genesisAmount = ownerTokens[user].length();
        genesisAmount = genesisAmount > 2 ? 2 : genesisAmount;
        uint256 pfpAmount = ownerPFPTokens[user].length();
        pfpAmount = pfpAmount > 2 ? 2 : pfpAmount;

        PoolInfo memory pool = poolInfo[pid];
        uint256 totalWeight = pool.totalWeight;
        if (totalWeight == 0) {
            return ret;
        }
        uint256 multi = (BasePoint +
            genesisAmount *
            buffPerNFT +
            pfpAmount *
            pfpBuffPerNFT);

        if (pid == 0) {
            //LP
            ret[0] =
                (pool.rewardTokenPerSecond[0] * 365 days * LPPrice * multi) /(totalWeight*esLionPrice * BasePoint * 1e4);
            //esLion
            ret[1] =
                (pool.rewardTokenPerSecond[1] *  365 days * 1e8 * multi) /(totalWeight * BasePoint);
        } else {
            //eth
            ret[0] =
                ((pool.rewardTokenPerSecond[0] * 365 days * ethPrice * 1e12) *
                    1e8 *
                    multi) /
                totalWeight /
                LPPrice /
                BasePoint;
            //LP
            ret[1] =
                ((pool.rewardTokenPerSecond[1] * 365 days) * 1e8 * multi) /
                totalWeight /
                BasePoint;
            //esLion
            ret[2] =
                ((pool.rewardTokenPerSecond[2] *
                    365 days *
                    esLionPrice *
                    1e12) *
                    1e8 *
                    multi) /
                totalWeight /
                LPPrice /
                BasePoint;
        }
    }

    function setDuration(uint256 _duration) external onlyOwner {
        duration = _duration;
    }

    function setPFPNFT(
        ILionDexNFT _lionPFPNFT
    ) external onlyOwner {
        lionPFPNFT = _lionPFPNFT;
    }

    function setFeeLPAmountPerNFT(
        uint256 _feeLPAmountPerNFT
    ) external onlyOwner {
        feeLPAmountPerNFT = _feeLPAmountPerNFT;
    }

    function setLionTokenAmountPerNFT(
        uint256 _lionTokenAmountPerNFT
    ) external onlyOwner {
        lionTokenAmountPerNFT = _lionTokenAmountPerNFT;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    receive() external payable {}
}

