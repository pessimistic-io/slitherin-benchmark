import "./Ownable.sol";
import "./ERC721.sol";
import "./IERC721Receiver.sol";
import "./IERC20.sol";
import "./ERC20.sol";
import "./ReentrancyGuard.sol";

import "./SafeMath.sol";
import "./SafeERC20.sol";


pragma solidity >0.6.12;

contract Whitelist is Ownable {
    mapping(address => bool) private _whitelist;
    bool private _disable;                      // default - false means whitelist feature is working on. if true no more use of whitelist

    event Whitelisted(address indexed _address, bool whitelist);
    event EnableWhitelist();
    event DisableWhitelist();

    modifier onlyWhitelisted {
        require(_disable || _whitelist[msg.sender], "Whitelist: caller is not on the whitelist");
        _;
    }

    function isWhitelist(address _address) public view returns (bool) {
        return _whitelist[_address];
    }

    function setWhitelist(address _address, bool _on) external onlyOwner {
        _whitelist[_address] = _on;

        emit Whitelisted(_address, _on);
    }

    function disableWhitelist(bool disable) external onlyOwner {
        _disable = disable;
        if (disable) {
            emit DisableWhitelist();
        } else {
            emit EnableWhitelist();
        }
    }
}


// File contracts/ArbiTenMasterChef.sol


pragma solidity >0.6.12;

import "./IMintableERC20.sol";
import "./ITreasury.sol";

import "./MintableERC20.sol";


library ERC20FactoryLib {
    function createERC20(string memory name_, string memory symbol_, uint8 decimals) external returns(address) 
    {
        ERC20 token = new MintableERC20(name_, symbol_, decimals);
        return address(token);
    }
}

interface IArbiTenToken {
    function mint(address _to, uint _amount) external;
    function balanceOf(address account) external view returns (uint);
    function transfer(address recipient, uint amount) external returns (bool);
}

interface I10SHAREToken {
    function mint(address _to, uint _amount) external;
    function balanceOf(address account) external view returns (uint);
    function transfer(address recipient, uint amount) external returns (bool);
}

contract ArbiTenMasterChef is Ownable, IERC721Receiver, ReentrancyGuard, Whitelist {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint amount;         // How many LP tokens the user has provided.
        uint rewardDebtArbiTen;     // Reward debt. See explanation below.
        uint rewardDebt10SHARE;     // Reward debt. See explanation below.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;              // Address of LP token contract.
        uint totalLocked;
        uint allocPointArbiTen;      // How many allocation points assigned to this pool. ArbiTen to distribute per block.
        uint allocPoint10SHARE;   // How many allocation points assigned to this pool. 10SHARE to distribute per block.
        uint lastRewardTime;      // Last block number that USDT distribution occurs.
        uint accArbiTenPerShare;     // Accumulated USDT per share, times 1e24. See below.
        uint acc10SHAREPerShare;  // Accumulated USDT per share, times 1e24. See below.
        uint depositFeeBP;        // Deposit fee in basis points
        address receiptToken;
        bool hasReceiptToken;
    }

    struct NFTSlot {
        address slot1;
        uint tokenId1;
        address slot2;
        uint tokenId2;
        address slot3;
        uint tokenId3;
        address slot4;
        uint tokenId4;
        address slot5;
        uint tokenId5;
    }

    struct NFTRatePair {
        uint rateArbiTen;
        uint rate10SHARE;
    }

    struct NFTIdRateRange {
        uint nftIdStart;
        uint nftIdEnd;
        uint rateArbiTen;
        uint rate10SHARE;
    }

    address BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    // The ArbiTen TOKEN!
    IArbiTenToken public ArbiTen;
    // ArbiTen tokens created per block.
    uint public ArbiTenPerSecond;
    // The 10SHARE TOKEN!
    I10SHAREToken public _10SHARE;
    // 10SHARE tokens created per block.
    uint public _10SHAREPerSecond;

    ITreasury treasury;

    address public reserveFund;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint => mapping(address => UserInfo)) public userInfo;
    mapping(address => bool) public isWhitelistedNFT;
    mapping(address => NFTRatePair) public nftBoost;
    mapping(address => NFTIdRateRange[]) public nftIdBoosters;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint public totalAllocPointArbiTen;
    uint public totalAllocPoint10SHARE;
    // The block number when mining starts.
    uint public startTime;

    mapping(address => bool) public receiptExistence;
    mapping(IERC20 => bool) public poolExistence;
    mapping(address => mapping(uint => NFTSlot)) private _depositedNFT; // user => pid => nft slot;

    bool public whitelistAll;
    uint public nftBaseBoostRate = 100;

    event Deposit(address indexed user, uint indexed pid, uint amount);
    event Withdraw(address indexed user, uint indexed pid, uint amount);
    event EmergencyWithdraw(address indexed user, uint indexed pid, uint amount);
    event UpdateArbiTenEmissionRate(address indexed user, uint ArbiTenPerSecond);
    event Update10SHAREEmissionRate(address indexed user, uint _10SHAREPerSecond);
    event UpdateNftBaseBoostRate(address indexed user, uint rate);
    event UpdateNFTSpecificBoostRate(address indexed user, address indexed _nft, uint rate10ArbiTen, uint rate10SHARE);
    event UpdateNFTIdSpecificBoostRate(address indexed user, address indexed _nft, uint _nftIdStart, uint _nftIdEnd, uint rate10ArbiTen, uint rate10SHARE);
    event RemoveNFTIdSpecificBoostRate(address indexed user, address indexed _nft, uint index);
    event UpdateNFTWhitelist(address indexed user, address indexed _nft, bool enabled);
    event UpdateNewReserveFund(address newReserveFund);
    event ReferralCommissionPaid(address indexed user, address indexed referrer, uint commissionAmount);

    function onERC721Received(
        address,
        address,
        uint,
        bytes calldata
    ) external override returns(bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    constructor(
        IArbiTenToken _ArbiTen,
        uint _ArbiTenPerSecond,
        I10SHAREToken __10SHARE,
        uint __10SHAREPerSecond,
        uint _startTime,
        ITreasury _treasury
    ) public {
        ArbiTen = _ArbiTen;
        ArbiTenPerSecond = _ArbiTenPerSecond;

        _10SHARE = __10SHARE;
        _10SHAREPerSecond = __10SHAREPerSecond;

        totalAllocPointArbiTen = 0;
        totalAllocPoint10SHARE = 0;

        startTime = _startTime;
        whitelistAll = false;

        treasury = _treasury;

        reserveFund = msg.sender;
    }

    /* ========== Modifiers ========== */


    modifier nonDuplicated(IERC20 _lpToken) {
        require(poolExistence[_lpToken] == false, "nonDuplicated: duplicated");
        _;
    }

    modifier nonContract() {
        if (!isWhitelist(msg.sender) && !whitelistAll) {
            require(tx.origin == msg.sender);
        }
        _;
    }

    /* ========== NFT View Functions ========== */

    function getNftIdBoosters(address _nft, uint index) public view returns (NFTIdRateRange memory) {
        return nftIdBoosters[_nft][index];
    }

    function getBoostRateArbiTen(address _nft, uint _nftId) public view returns (uint) {
        if (nftIdBoosters[_nft].length == 0)
            return nftBoost[_nft].rateArbiTen;
        else {
            for (uint i = 0;i<nftIdBoosters[_nft].length;i++) {
                if (_nftId >= nftIdBoosters[_nft][i].nftIdStart && _nftId <= nftIdBoosters[_nft][i].nftIdEnd)
                    return nftIdBoosters[_nft][i].rateArbiTen;
            }
        }
        return nftBoost[_nft].rateArbiTen;
    }

    function getBoostRate10SHARE(address _nft, uint _nftId) public view returns (uint) {
        if (nftIdBoosters[_nft].length == 0)
            return nftBoost[_nft].rate10SHARE;
        else {
            for (uint i = 0;i<nftIdBoosters[_nft].length;i++) {
                if (_nftId >= nftIdBoosters[_nft][i].nftIdStart && _nftId <= nftIdBoosters[_nft][i].nftIdEnd)
                    return nftIdBoosters[_nft][i].rate10SHARE;
            }
        }
        return nftBoost[_nft].rate10SHARE;
    }

    function getBoostArbiTen(address _account, uint _pid) public view returns (uint) {
        NFTSlot memory slot = _depositedNFT[_account][_pid];
        uint boost1 = getBoostRateArbiTen(slot.slot1, slot.tokenId1);
        uint boost2 = getBoostRateArbiTen(slot.slot2, slot.tokenId2);
        uint boost3 = getBoostRateArbiTen(slot.slot3, slot.tokenId3);
        uint boost4 = getBoostRateArbiTen(slot.slot4, slot.tokenId4);
        uint boost5 = getBoostRateArbiTen(slot.slot5, slot.tokenId5);
        uint boost = boost1 + boost2 + boost3 + boost4 + boost5;
        return boost.mul(nftBaseBoostRate).div(100); // boosts from 0% onwards
    }

    function getBoost10SHARE(address _account, uint _pid) public view returns (uint) {
        NFTSlot memory slot = _depositedNFT[_account][_pid];
        uint boost1 = getBoostRate10SHARE(slot.slot1, slot.tokenId1);
        uint boost2 = getBoostRate10SHARE(slot.slot2, slot.tokenId2);
        uint boost3 = getBoostRate10SHARE(slot.slot3, slot.tokenId3);
        uint boost4 = getBoostRate10SHARE(slot.slot4, slot.tokenId4);
        uint boost5 = getBoostRate10SHARE(slot.slot5, slot.tokenId5);
        uint boost = boost1 + boost2 + boost3 + boost4 + boost5;
        return boost.mul(nftBaseBoostRate).div(100); // boosts from 0% onwards
    }

    function getSlots(address _account, uint _pid) public view returns (address, address, address, address, address) {
        NFTSlot memory slot = _depositedNFT[_account][_pid];
        return (slot.slot1, slot.slot2, slot.slot3, slot.slot4, slot.slot5);
    }

    function getTokenIds(address _account, uint _pid) public view returns (uint, uint, uint, uint, uint) {
        NFTSlot memory slot = _depositedNFT[_account][_pid];
        return (slot.tokenId1, slot.tokenId2, slot.tokenId3, slot.tokenId4, slot.tokenId5);
    }

    /* ========== View Functions ========== */

    function poolLength() external view returns (uint) {
        return poolInfo.length;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint _from, uint _to) public pure returns (uint) {
        return _to.sub(_from);
    }

    // View function to see pending USDT on frontend.
    function pendingArbiTen(uint _pid, address _user) external view returns (uint) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint accArbiTenPerShare = pool.accArbiTenPerShare;
        uint lpSupply = pool.totalLocked;
        if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            uint multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
            uint ArbiTenReward = multiplier.mul(ArbiTenPerSecond).mul(pool.allocPointArbiTen).div(totalAllocPointArbiTen);
            accArbiTenPerShare = accArbiTenPerShare.add(ArbiTenReward.mul(1e24).div(lpSupply));
        }
        return user.amount.mul(accArbiTenPerShare).div(1e24).sub(user.rewardDebtArbiTen);
    }

    // View function to see pending USDT on frontend.
    function pending10SHARE(uint _pid, address _user) external view returns (uint) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint acc10SHAREPerShare = pool.acc10SHAREPerShare;
        uint lpSupply = pool.totalLocked;
        if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            uint multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
            uint _10SHAREReward = multiplier.mul(_10SHAREPerSecond).mul(pool.allocPoint10SHARE).div(totalAllocPoint10SHARE);
            acc10SHAREPerShare = acc10SHAREPerShare.add(_10SHAREReward.mul(1e24).div(lpSupply));
        }
        return user.amount.mul(acc10SHAREPerShare).div(1e24).sub(user.rewardDebt10SHARE);
    }

    /* ========== Owner Functions ========== */

    // Add a new lp to the pool. Can only be called by the owner.
    function add(uint _allocPointArbiTen, uint _allocPoint10SHARE, ERC20 _lpToken, bool _withUpdate, uint _depositFeeBP, bool _hasReceiptToken, string memory receiptName) public onlyOwner nonDuplicated(_lpToken) {
        require(_depositFeeBP <= 1000, "too high fee"); // <= 10%

        if (_withUpdate) {
            massUpdatePools();
        }

        address receiptTokenAddress = address(0);

        if (_hasReceiptToken)
            receiptTokenAddress = ERC20FactoryLib.createERC20(receiptName, receiptName, _lpToken.decimals());

        uint lastRewardTime = block.timestamp > startTime ? block.timestamp : startTime;
        totalAllocPointArbiTen = totalAllocPointArbiTen.add(_allocPointArbiTen);
        totalAllocPoint10SHARE = totalAllocPoint10SHARE.add(_allocPoint10SHARE);
        poolExistence[_lpToken] = true;
        poolInfo.push(PoolInfo({
            lpToken : _lpToken,
            allocPointArbiTen : _allocPointArbiTen,
            allocPoint10SHARE : _allocPoint10SHARE,
            lastRewardTime : lastRewardTime,
            accArbiTenPerShare : 0,
            acc10SHAREPerShare : 0,
            depositFeeBP: _depositFeeBP,
            totalLocked: 0,
            receiptToken: receiptTokenAddress,
            hasReceiptToken: _hasReceiptToken
        }));
    }

    // Update the given pool's USDT allocation point and deposit fee. Can only be called by the owner.
    function set(uint _pid, uint _allocPointArbiTen, uint _allocPoint10SHARE, bool _withUpdate, uint _depositFeeBP) public onlyOwner {
        require(_depositFeeBP <= 1000, "too high fee"); // <= 10%
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPointArbiTen = totalAllocPointArbiTen.sub(poolInfo[_pid].allocPointArbiTen).add(_allocPointArbiTen);
        totalAllocPoint10SHARE = totalAllocPoint10SHARE.sub(poolInfo[_pid].allocPoint10SHARE).add(_allocPoint10SHARE);
        poolInfo[_pid].allocPointArbiTen = _allocPointArbiTen;
        poolInfo[_pid].allocPoint10SHARE = _allocPoint10SHARE;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
    }

    /* ========== NFT External Functions ========== */

    // Depositing of NFTs
    function depositNFT(address _nft, uint _tokenId, uint _slot, uint _pid) public nonContract {
        require(_slot != 0 && _slot <= 5, "slot out of range 1-5!");
        require(isWhitelistedNFT[_nft], "only approved NFTs");
        require(ERC721(_nft).balanceOf(msg.sender) > 0, "user does not have specified NFT");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        //require(user.amount == 0, "not allowed to deposit");

        updatePool(_pid);
        transferPendingRewards(_pid);
        
        user.rewardDebtArbiTen = user.amount.mul(pool.accArbiTenPerShare).div(1e24);
        user.rewardDebt10SHARE = user.amount.mul(pool.acc10SHAREPerShare).div(1e24);

        NFTSlot memory slot = _depositedNFT[msg.sender][_pid];

        address existingNft;

        if (_slot == 1) existingNft = slot.slot1;
        else if (_slot == 2) existingNft = slot.slot2;
        else if (_slot == 3) existingNft = slot.slot3;
        else if (_slot == 4) existingNft = slot.slot4;
        else if (_slot == 5) existingNft = slot.slot5;

        require(existingNft == address(0), "you must empty this slot before depositing a new nft here!");

        if (_slot == 1) slot.slot1 = _nft;
        else if (_slot == 2) slot.slot2 = _nft;
        else if (_slot == 3) slot.slot3 = _nft;
        else if (_slot == 4) slot.slot4 = _nft;
        else if (_slot == 5) slot.slot5 = _nft;
        
        if (_slot == 1) slot.tokenId1 = _tokenId;
        else if (_slot == 2) slot.tokenId2 = _tokenId;
        else if (_slot == 3) slot.tokenId3 = _tokenId;
        else if (_slot == 4) slot.tokenId4 = _tokenId;
        else if (_slot == 5) slot.tokenId5 = _tokenId;

        _depositedNFT[msg.sender][_pid] = slot;

        ERC721(_nft).transferFrom(msg.sender, address(this), _tokenId);
    }

    // Withdrawing of NFTs
    function withdrawNFT(uint _slot, uint _pid) public nonContract {
        address _nft;
        uint _tokenId;

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        updatePool(_pid);
        transferPendingRewards(_pid);
        
        user.rewardDebtArbiTen = user.amount.mul(pool.accArbiTenPerShare).div(1e24);
        user.rewardDebt10SHARE = user.amount.mul(pool.acc10SHAREPerShare).div(1e24);

        NFTSlot memory slot = _depositedNFT[msg.sender][_pid];

        if (_slot == 1) _nft = slot.slot1;
        else if (_slot == 2) _nft = slot.slot2;
        else if (_slot == 3) _nft = slot.slot3;
        else if (_slot == 4) _nft = slot.slot4;
        else if (_slot == 5) _nft = slot.slot5;
        
        if (_slot == 1) _tokenId = slot.tokenId1;
        else if (_slot == 2) _tokenId = slot.tokenId2;
        else if (_slot == 3) _tokenId = slot.tokenId3;
        else if (_slot == 4) _tokenId = slot.tokenId4;
        else if (_slot == 5) _tokenId = slot.tokenId5;

        if (_slot == 1) slot.slot1 = address(0);
        else if (_slot == 2) slot.slot2 = address(0);
        else if (_slot == 3) slot.slot3 = address(0);
        else if (_slot == 4) slot.slot4 = address(0);
        else if (_slot == 5) slot.slot5 = address(0);
        
        if (_slot == 1) slot.tokenId1 = uint(0);
        else if (_slot == 2) slot.tokenId2 = uint(0);
        else if (_slot == 3) slot.tokenId3 = uint(0);
        else if (_slot == 4) slot.tokenId4 = uint(0);
        else if (_slot == 5) slot.tokenId5 = uint(0);

        _depositedNFT[msg.sender][_pid] = slot;
        
        ERC721(_nft).transferFrom(address(this), msg.sender, _tokenId);
    }

    /* ========== External Functions ========== */

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint length = poolInfo.length;
        for (uint pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }
        uint lpSupply = pool.totalLocked;
        if (lpSupply == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }

        uint multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);

        if (pool.allocPointArbiTen > 0) {
            uint ArbiTenReward = multiplier.mul(ArbiTenPerSecond).mul(pool.allocPointArbiTen).div(totalAllocPointArbiTen);
            if (ArbiTenReward > 0) {
                ArbiTen.mint(address(this), ArbiTenReward);
                pool.accArbiTenPerShare = pool.accArbiTenPerShare.add(ArbiTenReward.mul(1e24).div(lpSupply));
            }
        }

        if (pool.allocPoint10SHARE > 0) {
            uint _10SHAREReward = multiplier.mul(_10SHAREPerSecond).mul(pool.allocPoint10SHARE).div(totalAllocPoint10SHARE);
            if (_10SHAREReward > 0) {
                _10SHARE.mint(address(this), _10SHAREReward);
                pool.acc10SHAREPerShare = pool.acc10SHAREPerShare.add(_10SHAREReward.mul(1e24).div(lpSupply));
            }
        }

        pool.lastRewardTime = block.timestamp;
    }

    function transferPendingRewards(uint _pid) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        if (user.amount > 0) {
            uint pendingArbiTenToPay = user.amount.mul(pool.accArbiTenPerShare).div(1e24).sub(user.rewardDebtArbiTen);
            if (pendingArbiTenToPay > 0) {
                safeArbiTenTransfer(msg.sender, pendingArbiTenToPay, _pid);
            }// here
            uint pending10SHAREToPay = user.amount.mul(pool.acc10SHAREPerShare).div(1e24).sub(user.rewardDebt10SHARE);
            if (pending10SHAREToPay > 0) {
                safe10SHARETransfer(msg.sender, pending10SHAREToPay, _pid);
            }
        }
    }

    // Deposit LP tokens to MasterChef for ArbiTen allocation.
    function deposit(uint _pid, uint _amount) public nonReentrant nonContract {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        transferPendingRewards(_pid);

        if (_amount > 0) {
            if (pool.hasReceiptToken)
                MintableERC20(pool.receiptToken).mint(msg.sender, _amount);
            pool.lpToken.safeTransferFrom(msg.sender, address(this), _amount);
            if (pool.depositFeeBP > 0) {
                uint _depositFee = _amount.mul(pool.depositFeeBP).div(10000);
                pool.lpToken.safeTransfer(reserveFund, _depositFee);
                user.amount = user.amount.add(_amount).sub(_depositFee);
                pool.totalLocked = pool.totalLocked.add(_amount).sub(_depositFee);
            } else {
                user.amount = user.amount.add(_amount);
                pool.totalLocked = pool.totalLocked.add(_amount);
            }
        }
        user.rewardDebtArbiTen = user.amount.mul(pool.accArbiTenPerShare).div(1e24);
        user.rewardDebt10SHARE = user.amount.mul(pool.acc10SHAREPerShare).div(1e24);
        emit Deposit(msg.sender, _pid, _amount);

        ITreasury(treasury).treasuryUpdates();
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint _pid, uint _amount) public nonReentrant nonContract {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        transferPendingRewards(_pid);

        if (_amount > 0) {
            if (pool.hasReceiptToken)
                MintableERC20(pool.receiptToken).burn(msg.sender, _amount);
            user.amount = user.amount.sub(_amount);
            pool.totalLocked = pool.totalLocked.sub(_amount);
            pool.lpToken.safeTransfer(msg.sender, _amount);
        }
        user.rewardDebtArbiTen = user.amount.mul(pool.accArbiTenPerShare).div(1e24);
        user.rewardDebt10SHARE = user.amount.mul(pool.acc10SHAREPerShare).div(1e24);
        emit Withdraw(msg.sender, _pid, _amount);

        ITreasury(treasury).treasuryUpdates();
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint amount = user.amount;
        user.amount = 0;
        user.rewardDebtArbiTen = 0;
        user.rewardDebt10SHARE = 0;

        // In the case of an accounting error, we choose to let the user emergency withdraw anyway
        if (pool.totalLocked >=  amount)
            pool.totalLocked = pool.totalLocked - amount;
        else
            pool.totalLocked = 0;

        if (pool.hasReceiptToken)
            MintableERC20(pool.receiptToken).burn(msg.sender, amount);

        pool.lpToken.safeTransfer(msg.sender, amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe ArbiTen transfer function, just in case if rounding error causes pool to not have enough ArbiTen.
    function safeArbiTenTransfer(address _to, uint _amount, uint _pid) internal {
        uint boost = 0;
        ArbiTen.transfer(_to, _amount);
        boost = getBoostArbiTen(_to, _pid).mul(_amount).div(100);
        if (boost > 0) ArbiTen.mint(_to, boost);
    }

    // Safe 10SHARE transfer function, just in case if rounding error causes pool to not have enough 10SHARE.
    function safe10SHARETransfer(address _to, uint _amount, uint _pid) internal {
        uint boost = 0;
        _10SHARE.transfer(_to, _amount);
        boost = getBoost10SHARE(_to, _pid).mul(_amount).div(100);
        if (boost > 0) _10SHARE.mint(_to, boost);
    }

    /* ========== Set Variable Functions ========== */

    function updateArbiTenEmissionRate(uint _ArbiTenPerSecond) public onlyOwner {
        require(_ArbiTenPerSecond < 1e22, "emissions too high!");
        massUpdatePools();
        ArbiTenPerSecond = _ArbiTenPerSecond;
        emit UpdateArbiTenEmissionRate(msg.sender, _ArbiTenPerSecond);
    }

    function update10SHAREEmissionRate(uint __10SHAREPerSecond) public onlyOwner {
        require(__10SHAREPerSecond < 1e22, "emissions too high!");
        massUpdatePools();
        _10SHAREPerSecond = __10SHAREPerSecond;
        emit Update10SHAREEmissionRate(msg.sender, __10SHAREPerSecond);
    }

    function setNftBaseBoostRate(uint _rate) public onlyOwner {
        require(_rate < 500, "boost must be within range");
        nftBaseBoostRate = _rate;
        emit UpdateNftBaseBoostRate(msg.sender, _rate);
    }

    function setNftSpecificBoost(address _nft, uint _rateArbiTen, uint _rate10SHARE) public onlyOwner {
        require(_rateArbiTen <= 15, "boost must be within range");
        require(_rate10SHARE <= 15, "boost must be within range");
        nftBoost[_nft].rateArbiTen = _rateArbiTen;
        nftBoost[_nft].rate10SHARE = _rate10SHARE;
        emit UpdateNFTSpecificBoostRate(msg.sender, _nft, _rateArbiTen, _rate10SHARE);
    }

    function setNftIdSpecificBoostRange(address _nft, uint _nftIdStart, uint _nftIdEnd, uint _rateArbiTen, uint _rate10SHARE) public onlyOwner {
        require(_rateArbiTen <= 15, "boost must be within range");
        require(_rate10SHARE <= 15, "boost must be within range");
        require(_nftIdStart <= _nftIdEnd, "nftId start must be less than or equal to nftid end!");
        nftIdBoosters[_nft].push(NFTIdRateRange({
            nftIdStart: _nftIdStart,
            nftIdEnd: _nftIdEnd,
            rateArbiTen: _rateArbiTen,
            rate10SHARE: _rate10SHARE
        }));
        emit UpdateNFTIdSpecificBoostRate(msg.sender, _nft, _nftIdStart, _nftIdEnd, _rateArbiTen, _rate10SHARE);
    }

    function removeNftIdBoostRangeById(address _nft, uint index) public onlyOwner {
        nftIdBoosters[_nft][index] = nftIdBoosters[_nft][nftIdBoosters[_nft].length - 1];
        nftIdBoosters[_nft].pop();
        emit RemoveNFTIdSpecificBoostRate(msg.sender, _nft, index);
    }

    function setNftWhitelist(address _nft, bool enabled) public onlyOwner {
        isWhitelistedNFT[_nft] = enabled;
        emit UpdateNFTWhitelist(msg.sender, _nft, enabled);
    }

    function setReserveFund(address newReserveFund) public onlyOwner {
        reserveFund = newReserveFund;
        emit UpdateNewReserveFund(newReserveFund);
    }

    function flipWhitelistAll() public onlyOwner {
        whitelistAll = !whitelistAll;
    }

    function harvestAllRewards() public {
        uint length = poolInfo.length;
        for (uint pid = 0; pid < length; ++pid) {
            if (userInfo[pid][msg.sender].amount > 0) {
                withdraw(pid, 0);
            }
        }
    }
}
