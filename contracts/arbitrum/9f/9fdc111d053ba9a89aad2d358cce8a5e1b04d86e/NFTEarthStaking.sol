//SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

//
//     _   _______________________    ____  ________  __   ______________    __ __ _____   ________
//    / | / / ____/_  __/ ____/   |  / __ \/_  __/ / / /  / ___/_  __/   |  / //_//  _/ | / / ____/
//   /  |/ / /_    / / / __/ / /| | / /_/ / / / / /_/ /   \__ \ / / / /| | / ,<   / //  |/ / / __  
//  / /|  / __/   / / / /___/ ___ |/ _, _/ / / / __  /   ___/ // / / ___ |/ /| |_/ // /|  / /_/ /  
// /_/ |_/_/     /_/ /_____/_/  |_/_/ |_| /_/ /_/ /_/   /____//_/ /_/  |_/_/ |_/___/_/ |_/\____/ 

import "./IERC20.sol";
import "./SafeCast.sol";
import "./Ownable.sol";
import "./ERC721Enumerable.sol";

/**
 * @title NFTEarth Staking Contract
 * @notice Stake NFTE across four different pools that release hourly rewards
 */
contract NFTEarthStaking is Ownable {

    using SafeCast for uint256;
    using SafeCast for int256;

    /// @notice State for NFTE, Earthlings, RoboRover, and Pair Pools
    struct Pool {
        uint48 lastRewardedTimestampHour;
        uint16 lastRewardsRangeIndex;
        uint96 stakedAmount;
        uint96 accumulatedRewardsPerShare;
        TimeRange[] timeRanges;
    }

    /// @notice Pool rules valid for a given duration of time.
    /// @dev All TimeRange timestamp values must represent whole hours
    struct TimeRange {
        uint48 startTimestampHour;
        uint48 endTimestampHour;
        uint96 rewardsPerHour;
        uint96 capPerPosition;
    }

    /// @dev Convenience struct for front-end applications
    struct PoolUI {
        uint256 poolId;
        uint256 stakedAmount;
        TimeRange currentTimeRange;
    }

    /// @dev Per address amount and reward tracking
    struct Position {
        uint256 stakedAmount;
        int256 rewardsDebt;
    }
    mapping (address => Position) public addressPosition;

    /// @dev Struct for depositing and withdrawing from the EARTHLING and ROBOROVER NFT pools
    struct SingleNft {
        uint32 tokenId;
        uint224 amount;
    }
    /// @dev Struct for depositing from the NFW3C (Pair) pool
    struct PairNftDepositWithAmount {
        uint32 mainTokenId;
        uint32 nfw3cTokenId;
        uint184 amount;
    }
    /// @dev Struct for withdrawing from the NFW3C (Pair) pool
    struct PairNftWithdrawWithAmount {
        uint32 mainTokenId;
        uint32 nfw3cTokenId;
        uint184 amount;
        bool isUncommit;
    }
    /// @dev Struct for claiming from an NFT pool
    struct PairNft {
        uint128 mainTokenId;
        uint128 nfw3cTokenId;
    }
    /// @dev NFT paired status.  Can be used bi-directionally (EARTHLING/ROBOROVER -> NFW3C) or (NFW3C -> EARTHLING/ROBOROVER)
    struct PairingStatus {
        uint248 tokenId;
        bool isPaired;
    }

    // @dev UI focused payload
    struct DashboardStake {
        uint256 poolId;
        uint256 tokenId;
        uint256 deposited;
        uint256 unclaimed;
        uint256 rewards24hr;
        DashboardPair pair;
    }
    /// @dev Sub struct for DashboardStake
    struct DashboardPair {
        uint256 mainTokenId;
        uint256 mainTypePoolId;
    }
    /// @dev Placeholder for pair status, used by Nfte Pool
    DashboardPair private NULL_PAIR = DashboardPair(0, 0);

    /// @notice Internal Nfte amount for distributing staking reward claims
    IERC20 public immutable nfte;
    uint256 private constant APE_COIN_PRECISION = 1e18;
    uint256 private constant MIN_DEPOSIT = 1 * APE_COIN_PRECISION;
    uint256 private constant SECONDS_PER_HOUR = 3600;
    uint256 private constant SECONDS_PER_MINUTE = 60;

    uint256 constant NFTE_POOL_ID = 0;
    uint256 constant EARTHLING_POOL_ID = 1;
    uint256 constant ROBOROVER_POOL_ID = 2;
    uint256 constant NFW3C_POOL_ID = 3;
    Pool[4] public pools;

    /// @dev NFT contract mapping per pool
    mapping(uint256 => ERC721Enumerable) public nftContracts;
    /// @dev poolId => tokenId => nft position
    mapping(uint256 => mapping(uint256 => Position)) public nftPosition;
    /// @dev main type pool ID: 1: EARTHLING 2: ROBOROVER => main token ID => nfw3c token ID
    mapping(uint256 => mapping(uint256 => PairingStatus)) public mainToNfw3c;
    /// @dev nfw3c Token ID => main type pool ID: 1: EARTHLING 2: ROBOROVER => main token ID
    mapping(uint256 => mapping(uint256 => PairingStatus)) public nfw3cToMain;

    /** Custom Events */
    event UpdatePool(
        uint256 indexed poolId,
        uint256 lastRewardedBlock,
        uint256 stakedAmount,
        uint256 accumulatedRewardsPerShare
    );
    event Deposit(
        address indexed user,
        uint256 amount,
        address recipient
    );
    event DepositNft(
        address indexed user,
        uint256 indexed poolId,
        uint256 amount,
        uint256 tokenId
    );
    event DepositPairNft(
        address indexed user,
        uint256 amount,
        uint256 mainTypePoolId,
        uint256 mainTokenId,
        uint256 nfw3cTokenId
    );
    event Withdraw(
        address indexed user,
        uint256 amount,
        address recipient
    );
    event WithdrawNft(
        address indexed user,
        uint256 indexed poolId,
        uint256 amount,
        address recipient,
        uint256 tokenId
    );
    event WithdrawPairNft(
        address indexed user,
        uint256 amount,
        uint256 mainTypePoolId,
        uint256 mainTokenId,
        uint256 nfw3cTokenId
    );
    event ClaimRewards(
        address indexed user,
        uint256 amount,
        address recipient
    );
    event ClaimRewardsNft(
        address indexed user,
        uint256 indexed poolId,
        uint256 amount,
        uint256 tokenId
    );
    event ClaimRewardsPairNft(
        address indexed user,
        uint256 amount,
        uint256 mainTypePoolId,
        uint256 mainTokenId,
        uint256 nfw3cTokenId
    );

    error DepositMoreThanOneAPE();
    error InvalidPoolId();
    error StartMustBeGreaterThanEnd();
    error StartNotWholeHour();
    error EndNotWholeHour();
    error StartMustEqualLastEnd();
    error CallerNotOwner();
    error MainTokenNotOwnedOrPaired();
    error NFW3CNotOwnedOrPaired();
    error NFW3CAlreadyPaired();
    error ExceededCapAmount();
    error NotOwnerOfMain();
    error NotOwnerOfNFW3C();
    error ProvidedTokensNotPaired();
    error ExceededStakedAmount();
    error NeitherTokenInPairOwnedByCaller();
    error SplitPairCantPartiallyWithdraw();
    error UncommitWrongParameters();

    /**
     * @notice Construct a new Nfte Staking instance
     * @param _nfteContractAddress The Nfte ERC20 contract address
     * @param _earthlingContractAddress The EARTHLING NFT contract address
     * @param _roboroverContractAddress The ROBOROVER NFT contract address
     * @param _nfw3cContractAddress The NFW3C NFT contract address
     */
    constructor(
        address _nfteContractAddress,
        address _earthlingContractAddress,
        address _roboroverContractAddress,
        address _nfw3cContractAddress
    ) {
        nfte = IERC20(_nfteContractAddress);
        nftContracts[EARTHLING_POOL_ID] = ERC721Enumerable(_earthlingContractAddress);
        nftContracts[ROBOROVER_POOL_ID] = ERC721Enumerable(_roboroverContractAddress);
        nftContracts[NFW3C_POOL_ID] = ERC721Enumerable(_nfw3cContractAddress);
    }

    // Deposit/Commit Methods

    /**
     * @notice Deposit Nfte to the Nfte Pool
     * @param _amount Amount in Nfte
     * @param _recipient Address the deposit it stored to
     * @dev Nfte deposit must be >= 1 Nfte
     */
    function depositNfte(uint256 _amount, address _recipient) public {
        if (_amount < MIN_DEPOSIT) revert DepositMoreThanOneAPE();
        updatePool(NFTE_POOL_ID);

        Position storage position = addressPosition[_recipient];
        _deposit(NFTE_POOL_ID, position, _amount);

        nfte.transferFrom(msg.sender, address(this), _amount);

        emit Deposit(msg.sender, _amount, _recipient);
    }

    /**
     * @notice Deposit Nfte to the Nfte Pool
     * @param _amount Amount in Nfte
     * @dev Deposit on behalf of msg.sender. Nfte deposit must be >= 1 Nfte
     */
    function depositSelfNfte(uint256 _amount) external {
        depositNfte(_amount, msg.sender);
    }

    /**
     * @notice Deposit Nfte to the EARTHLING Pool
     * @param _nfts Array of SingleNft structs
     * @dev Commits 1 or more EARTHLING NFTs, each with an Nfte amount to the EARTHLING pool.\
     * Each EARTHLING committed must attach an Nfte amount >= 1 Nfte and <= the EARTHLING pool cap amount.
     */
    function depositEARTHLING(SingleNft[] calldata _nfts) external {
        _depositNft(EARTHLING_POOL_ID, _nfts);
    }

    /**
     * @notice Deposit Nfte to the ROBOROVER Pool
     * @param _nfts Array of SingleNft structs
     * @dev Commits 1 or more ROBOROVER NFTs, each with an Nfte amount to the ROBOROVER pool.\
     * Each ROBOROVER committed must attach an Nfte amount >= 1 Nfte and <= the ROBOROVER pool cap amount.
     */
    function depositROBOROVER(SingleNft[] calldata _nfts) external {
        _depositNft(ROBOROVER_POOL_ID, _nfts);
    }

    /**
     * @notice Deposit Nfte to the Pair Pool, where Pair = (EARTHLING + NFW3C) or (ROBOROVER + NFW3C)
     * @param _earthlingPairs Array of PairNftDepositWithAmount structs
     * @param _roboroverPairs Array of PairNftDepositWithAmount structs
     * @dev Commits 1 or more Pairs, each with an Nfte amount to the Pair pool.\
     * Each NFW3C committed must attach an Nfte amount >= 1 Nfte and <= the Pair pool cap amount.\
     * Example 1: EARTHLING + NFW3C + 1 Nfte:  [[0, 0, "1000000000000000000"],[]]\
     * Example 2: ROBOROVER + NFW3C + 1 Nfte:  [[], [0, 0, "1000000000000000000"]]\
     * Example 3: (EARTHLING + NFW3C + 1 Nfte) and (ROBOROVER + NFW3C + 1 Nfte): [[0, 0, "1000000000000000000"], [0, 1, "1000000000000000000"]]
     */
    function depositNFW3C(PairNftDepositWithAmount[] calldata _earthlingPairs, PairNftDepositWithAmount[] calldata _roboroverPairs) external {
        updatePool(NFW3C_POOL_ID);
        _depositPairNft(EARTHLING_POOL_ID, _earthlingPairs);
        _depositPairNft(ROBOROVER_POOL_ID, _roboroverPairs);
    }

    // Claim Rewards Methods

    /**
     * @notice Claim rewards for msg.sender and send to recipient
     * @param _recipient Address to send claim reward to
     */
    function claimNfte(address _recipient) public {
        updatePool(NFTE_POOL_ID);

        Position storage position = addressPosition[msg.sender];
        uint256 rewardsToBeClaimed = _claim(NFTE_POOL_ID, position, _recipient);

        emit ClaimRewards(msg.sender, rewardsToBeClaimed, _recipient);
    }

    /// @notice Claim and send rewards
    function claimSelfNfte() external {
        claimNfte(msg.sender);
    }

    /**
     * @notice Claim rewards for array of EARTHLING NFTs and send to recipient
     * @param _nfts Array of NFTs owned and committed by the msg.sender
     * @param _recipient Address to send claim reward to
     */
    function claimEARTHLING(uint256[] calldata _nfts, address _recipient) external {
        _claimNft(EARTHLING_POOL_ID, _nfts, _recipient);
    }

    /**
     * @notice Claim rewards for array of EARTHLING NFTs
     * @param _nfts Array of NFTs owned and committed by the msg.sender
     */
    function claimSelfEARTHLING(uint256[] calldata _nfts) external {
        _claimNft(EARTHLING_POOL_ID, _nfts, msg.sender);
    }

    /**
     * @notice Claim rewards for array of ROBOROVER NFTs and send to recipient
     * @param _nfts Array of NFTs owned and committed by the msg.sender
     * @param _recipient Address to send claim reward to
     */
    function claimROBOROVER(uint256[] calldata _nfts, address _recipient) external {
        _claimNft(ROBOROVER_POOL_ID, _nfts, _recipient);
    }

    /**
     * @notice Claim rewards for array of ROBOROVER NFTs
     * @param _nfts Array of NFTs owned and committed by the msg.sender
     */
    function claimSelfROBOROVER(uint256[] calldata _nfts) external {
        _claimNft(ROBOROVER_POOL_ID, _nfts, msg.sender);
    }

    /**
     * @notice Claim rewards for array of Paired NFTs and send to recipient
     * @param _earthlingPairs Array of Paired EARTHLING NFTs owned and committed by the msg.sender
     * @param _roboroverPairs Array of Paired ROBOROVER NFTs owned and committed by the msg.sender
     * @param _recipient Address to send claim reward to
     */
    function claimNFW3C(PairNft[] calldata _earthlingPairs, PairNft[] calldata _roboroverPairs, address _recipient) public {
        updatePool(NFW3C_POOL_ID);
        _claimPairNft(EARTHLING_POOL_ID, _earthlingPairs, _recipient);
        _claimPairNft(ROBOROVER_POOL_ID, _roboroverPairs, _recipient);
    }

    /**
     * @notice Claim rewards for array of Paired NFTs
     * @param _earthlingPairs Array of Paired EARTHLING NFTs owned and committed by the msg.sender
     * @param _roboroverPairs Array of Paired ROBOROVER NFTs owned and committed by the msg.sender
     */
    function claimSelfNFW3C(PairNft[] calldata _earthlingPairs, PairNft[] calldata _roboroverPairs) external {
        claimNFW3C(_earthlingPairs, _roboroverPairs, msg.sender);
    }

    // Uncommit/Withdraw Methods

    /**
     * @notice Withdraw staked Nfte from the Nfte pool.  Performs an automatic claim as part of the withdraw process.
     * @param _amount Amount of Nfte
     * @param _recipient Address to send withdraw amount and claim to
     */
    function withdrawNfte(uint256 _amount, address _recipient) public {
        updatePool(NFTE_POOL_ID);

        Position storage position = addressPosition[msg.sender];
        if (_amount == position.stakedAmount) {
            uint256 rewardsToBeClaimed = _claim(NFTE_POOL_ID, position, _recipient);
            emit ClaimRewards(msg.sender, rewardsToBeClaimed, _recipient);
        }
        _withdraw(NFTE_POOL_ID, position, _amount);

        nfte.transfer(_recipient, _amount);

        emit Withdraw(msg.sender, _amount, _recipient);
    }

    /**
     * @notice Withdraw staked Nfte from the Nfte pool.  If withdraw is total staked amount, performs an automatic claim.
     * @param _amount Amount of Nfte
     */
    function withdrawSelfNfte(uint256 _amount) external {
        withdrawNfte(_amount, msg.sender);
    }

    /**
     * @notice Withdraw staked Nfte from the EARTHLING pool.  If withdraw is total staked amount, performs an automatic claim.
     * @param _nfts Array of EARTHLING NFT's with staked amounts
     * @param _recipient Address to send withdraw amount and claim to
     */
    function withdrawEARTHLING(SingleNft[] calldata _nfts, address _recipient) external {
        _withdrawNft(EARTHLING_POOL_ID, _nfts, _recipient);
    }

    /**
     * @notice Withdraw staked Nfte from the EARTHLING pool.  If withdraw is total staked amount, performs an automatic claim.
     * @param _nfts Array of EARTHLING NFT's with staked amounts
     */
    function withdrawSelfEARTHLING(SingleNft[] calldata _nfts) external {
        _withdrawNft(EARTHLING_POOL_ID, _nfts, msg.sender);
    }

    /**
     * @notice Withdraw staked Nfte from the ROBOROVER pool.  If withdraw is total staked amount, performs an automatic claim.
     * @param _nfts Array of ROBOROVER NFT's with staked amounts
     * @param _recipient Address to send withdraw amount and claim to
     */
    function withdrawROBOROVER(SingleNft[] calldata _nfts, address _recipient) external {
        _withdrawNft(ROBOROVER_POOL_ID, _nfts, _recipient);
    }

    /**
     * @notice Withdraw staked Nfte from the ROBOROVER pool.  If withdraw is total staked amount, performs an automatic claim.
     * @param _nfts Array of ROBOROVER NFT's with staked amounts
     */
    function withdrawSelfROBOROVER(SingleNft[] calldata _nfts) external {
        _withdrawNft(ROBOROVER_POOL_ID, _nfts, msg.sender);
    }

    /**
     * @notice Withdraw staked Nfte from the Pair pool.  If withdraw is total staked amount, performs an automatic claim.
     * @param _earthlingPairs Array of Paired EARTHLING NFT's with staked amounts and isUncommit boolean
     * @param _roboroverPairs Array of Paired ROBOROVER NFT's with staked amounts and isUncommit boolean
     * @dev if pairs have split ownership and NFW3C is attempting a withdraw, the withdraw must be for the total staked amount
     */
    function withdrawNFW3C(PairNftWithdrawWithAmount[] calldata _earthlingPairs, PairNftWithdrawWithAmount[] calldata _roboroverPairs) external {
        updatePool(NFW3C_POOL_ID);
        _withdrawPairNft(EARTHLING_POOL_ID, _earthlingPairs);
        _withdrawPairNft(ROBOROVER_POOL_ID, _roboroverPairs);
    }

    // Time Range Methods

    /**
     * @notice Add single time range with a given rewards per hour for a given pool
     * @dev In practice one Time Range will represent one quarter (defined by `_startTimestamp`and `_endTimeStamp` as whole hours)
     * where the rewards per hour is constant for a given pool.
     * @param _poolId Available pool values 0-3
     * @param _amount Total amount of Nfte to be distributed over the range
     * @param _startTimestamp Whole hour timestamp representation
     * @param _endTimeStamp Whole hour timestamp representation
     * @param _capPerPosition Per position cap amount determined by poolId
     */
    function addTimeRange(
        uint256 _poolId,
        uint256 _amount,
        uint256 _startTimestamp,
        uint256 _endTimeStamp,
        uint256 _capPerPosition) external onlyOwner
    {
        if (_poolId > NFW3C_POOL_ID) revert InvalidPoolId();
        if (_startTimestamp >= _endTimeStamp) revert StartMustBeGreaterThanEnd();
        if (getMinute(_startTimestamp) > 0 || getSecond(_startTimestamp) > 0) revert StartNotWholeHour();
        if (getMinute(_endTimeStamp) > 0 || getSecond(_endTimeStamp) > 0) revert EndNotWholeHour();

        Pool storage pool = pools[_poolId];
        uint256 length = pool.timeRanges.length;
        if (length > 0) {
            if (_startTimestamp != pool.timeRanges[length - 1].endTimestampHour) revert StartMustEqualLastEnd();
        }

        uint256 hoursInSeconds = _endTimeStamp - _startTimestamp;
        uint256 rewardsPerHour = _amount * SECONDS_PER_HOUR / hoursInSeconds;

        TimeRange memory next = TimeRange(_startTimestamp.toUint48(), _endTimeStamp.toUint48(),
            rewardsPerHour.toUint96(), _capPerPosition.toUint96());
        pool.timeRanges.push(next);
    }

    /**
     * @notice Removes the last Time Range for a given pool.
     * @param _poolId Available pool values 0-3
     */
    function removeLastTimeRange(uint256 _poolId) external onlyOwner {
        pools[_poolId].timeRanges.pop();
    }

    /**
     * @notice Lookup method for a TimeRange struct
     * @return TimeRange A Pool's timeRanges struct by index.
     * @param _poolId Available pool values 0-3
     * @param _index Target index in a Pool's timeRanges array
     */
    function getTimeRangeBy(uint256 _poolId, uint256 _index) public view returns (TimeRange memory) {
        return pools[_poolId].timeRanges[_index];
    }

    // Pool Methods

    /**
     * @notice Lookup available rewards for a pool over a given time range
     * @return uint256 The amount of Nfte rewards to be distributed by pool for a given time range
     * @return uint256 The amount of time ranges
     * @param _poolId Available pool values 0-3
     * @param _from Whole hour timestamp representation
     * @param _to Whole hour timestamp representation
     */
    function rewardsBy(uint256 _poolId, uint256 _from, uint256 _to) public view returns (uint256, uint256) {
        Pool memory pool = pools[_poolId];

        uint256 currentIndex = pool.lastRewardsRangeIndex;
        if(_to < pool.timeRanges[0].startTimestampHour) return (0, currentIndex);

        while(_from > pool.timeRanges[currentIndex].endTimestampHour && _to > pool.timeRanges[currentIndex].endTimestampHour) {
            unchecked {
                ++currentIndex;
            }
        }

        uint256 rewards;
        TimeRange memory current;
        uint256 startTimestampHour;
        uint256 endTimestampHour;
        uint256 length = pool.timeRanges.length;
        for(uint256 i = currentIndex; i < length;) {
            current = pool.timeRanges[i];
            startTimestampHour = _from <= current.startTimestampHour ? current.startTimestampHour : _from;
            endTimestampHour = _to <= current.endTimestampHour ? _to : current.endTimestampHour;

            rewards = rewards + (endTimestampHour - startTimestampHour) * current.rewardsPerHour / SECONDS_PER_HOUR;

            if(_to <= endTimestampHour) {
                return (rewards, i);
            }
            unchecked {
                ++i;
            }
        }

        return (rewards, length - 1);
    }

    /**
     * @notice Updates reward variables `lastRewardedTimestampHour`, `accumulatedRewardsPerShare` and `lastRewardsRangeIndex`
     * for a given pool.
     * @param _poolId Available pool values 0-3
     */
    function updatePool(uint256 _poolId) public {
        Pool storage pool = pools[_poolId];

        if (block.timestamp < pool.timeRanges[0].startTimestampHour) return;
        if (block.timestamp <= pool.lastRewardedTimestampHour + SECONDS_PER_HOUR) return;

        uint48 lastTimestampHour = pool.timeRanges[pool.timeRanges.length-1].endTimestampHour;
        uint48 previousTimestampHour = getPreviousTimestampHour().toUint48();

        if (pool.stakedAmount == 0) {
            pool.lastRewardedTimestampHour = previousTimestampHour > lastTimestampHour ? lastTimestampHour : previousTimestampHour;
            return;
        }

        (uint256 rewards, uint256 index) = rewardsBy(_poolId, pool.lastRewardedTimestampHour, previousTimestampHour);
        if (pool.lastRewardsRangeIndex != index) {
            pool.lastRewardsRangeIndex = index.toUint16();
        }
        pool.accumulatedRewardsPerShare = (pool.accumulatedRewardsPerShare + (rewards * APE_COIN_PRECISION) / pool.stakedAmount).toUint96();
        pool.lastRewardedTimestampHour = previousTimestampHour > lastTimestampHour ? lastTimestampHour : previousTimestampHour;

        emit UpdatePool(_poolId, pool.lastRewardedTimestampHour, pool.stakedAmount, pool.accumulatedRewardsPerShare);
    }

    // Read Methods

    function getCurrentTimeRangeIndex(Pool memory pool) private view returns (uint256) {
        uint256 current = pool.lastRewardsRangeIndex;

        if (block.timestamp < pool.timeRanges[current].startTimestampHour) return current;
        for(current = pool.lastRewardsRangeIndex; current < pool.timeRanges.length; ++current) {
            TimeRange memory currentTimeRange = pool.timeRanges[current];
            if (currentTimeRange.startTimestampHour <= block.timestamp && block.timestamp <= currentTimeRange.endTimestampHour) return current;
        }
        revert("distribution ended");
    }

    /**
     * @notice Fetches a PoolUI struct (poolId, stakedAmount, currentTimeRange) for each reward pool
     * @return PoolUI for Nfte.
     * @return PoolUI for EARTHLING.
     * @return PoolUI for ROBOROVER.
     * @return PoolUI for NFW3C.
     */
    function getPoolsUI() public view returns (PoolUI memory, PoolUI memory, PoolUI memory, PoolUI memory) {
        Pool memory nftePool = pools[0];
        Pool memory earthlingPool = pools[1];
        Pool memory roboroverPool = pools[2];
        Pool memory nfw3cPool = pools[3];
        uint256 current = getCurrentTimeRangeIndex(nftePool);
        return (PoolUI(0,nftePool.stakedAmount, nftePool.timeRanges[current]),
                PoolUI(1,earthlingPool.stakedAmount, earthlingPool.timeRanges[current]),
                PoolUI(2,roboroverPool.stakedAmount, roboroverPool.timeRanges[current]),
                PoolUI(3,nfw3cPool.stakedAmount, nfw3cPool.timeRanges[current]));
    }

    /**
     * @notice Fetches an address total staked amount, used by voting contract
     * @return amount uint256 staked amount for all pools.
     * @param _address An Ethereum address
     */
    function stakedTotal(address _address) external view returns (uint256) {
        uint256 total = addressPosition[_address].stakedAmount;

        total += _stakedTotal(EARTHLING_POOL_ID, _address);
        total += _stakedTotal(ROBOROVER_POOL_ID, _address);
        total += _stakedTotalPair(_address);

        return total;
    }

    function _stakedTotal(uint256 _poolId, address _addr) private view returns (uint256) {
        uint256 total = 0;
        uint256 nftCount = nftContracts[_poolId].balanceOf(_addr);
        for(uint256 i = 0; i < nftCount; ++i) {
            uint256 tokenId = nftContracts[_poolId].tokenOfOwnerByIndex(_addr, i);
            total += nftPosition[_poolId][tokenId].stakedAmount;
        }

        return total;
    }

    function _stakedTotalPair(address _addr) private view returns (uint256) {
        uint256 total = 0;

        uint256 nftCount = nftContracts[EARTHLING_POOL_ID].balanceOf(_addr);
        for(uint256 i = 0; i < nftCount; ++i) {
            uint256 earthlingTokenId = nftContracts[EARTHLING_POOL_ID].tokenOfOwnerByIndex(_addr, i);
            if (mainToNfw3c[EARTHLING_POOL_ID][earthlingTokenId].isPaired) {
                uint256 nfw3cTokenId = mainToNfw3c[EARTHLING_POOL_ID][earthlingTokenId].tokenId;
                total += nftPosition[NFW3C_POOL_ID][nfw3cTokenId].stakedAmount;
            }
        }

        nftCount = nftContracts[ROBOROVER_POOL_ID].balanceOf(_addr);
        for(uint256 i = 0; i < nftCount; ++i) {
            uint256 roboroverTokenId = nftContracts[ROBOROVER_POOL_ID].tokenOfOwnerByIndex(_addr, i);
            if (mainToNfw3c[ROBOROVER_POOL_ID][roboroverTokenId].isPaired) {
                uint256 nfw3cTokenId = mainToNfw3c[ROBOROVER_POOL_ID][roboroverTokenId].tokenId;
                total += nftPosition[NFW3C_POOL_ID][nfw3cTokenId].stakedAmount;
            }
        }

        return total;
    }

    /**
     * @notice Fetches a DashboardStake = [poolId, tokenId, deposited, unclaimed, rewards24Hrs, paired] \
     * for each pool, for an Ethereum address
     * @return dashboardStakes An array of DashboardStake structs
     * @param _address An Ethereum address
     */
    function getAllStakes(address _address) public view returns (DashboardStake[] memory) {

        DashboardStake memory nfteStake = getNfteStake(_address);
        DashboardStake[] memory earthlingStakes = getEarthlingStakes(_address);
        DashboardStake[] memory roboroverStakes = getRoboroverStakes(_address);
        DashboardStake[] memory nfw3cStakes = getNfw3cStakes(_address);
        DashboardStake[] memory splitStakes = getSplitStakes(_address);

        uint256 count = (earthlingStakes.length + roboroverStakes.length + nfw3cStakes.length + splitStakes.length + 1);
        DashboardStake[] memory allStakes = new DashboardStake[](count);

        uint256 offset = 0;
        allStakes[offset] = nfteStake;
        ++offset;

        for(uint256 i = 0; i < earthlingStakes.length; ++i) {
            allStakes[offset] = earthlingStakes[i];
            ++offset;
        }

        for(uint256 i = 0; i < roboroverStakes.length; ++i) {
            allStakes[offset] = roboroverStakes[i];
            ++offset;
        }

        for(uint256 i = 0; i < nfw3cStakes.length; ++i) {
            allStakes[offset] = nfw3cStakes[i];
            ++offset;
        }

        for(uint256 i = 0; i < splitStakes.length; ++i) {
            allStakes[offset] = splitStakes[i];
            ++offset;
        }

        return allStakes;
    }

    /**
     * @notice Fetches a DashboardStake for the Nfte pool
     * @return dashboardStake A dashboardStake struct
     * @param _address An Ethereum address
     */
    function getNfteStake(address _address) public view returns (DashboardStake memory) {
        uint256 tokenId = 0;
        uint256 deposited = addressPosition[_address].stakedAmount;
        uint256 unclaimed = deposited > 0 ? this.pendingRewards(0, _address, tokenId) : 0;
        uint256 rewards24Hrs = deposited > 0 ? _estimate24HourRewards(0, _address, 0) : 0;

        return DashboardStake(NFTE_POOL_ID, tokenId, deposited, unclaimed, rewards24Hrs, NULL_PAIR);
    }

    /**
     * @notice Fetches an array of DashboardStakes for the EARTHLING pool
     * @return dashboardStakes An array of DashboardStake structs
     */
    function getEarthlingStakes(address _address) public view returns (DashboardStake[] memory) {
        return _getStakes(_address, EARTHLING_POOL_ID);
    }

    /**
     * @notice Fetches an array of DashboardStakes for the ROBOROVER pool
     * @return dashboardStakes An array of DashboardStake structs
     */
    function getRoboroverStakes(address _address) public view returns (DashboardStake[] memory) {
        return _getStakes(_address, ROBOROVER_POOL_ID);
    }

    /**
     * @notice Fetches an array of DashboardStakes for the NFW3C pool
     * @return dashboardStakes An array of DashboardStake structs
     */
    function getNfw3cStakes(address _address) public view returns (DashboardStake[] memory) {
        return _getStakes(_address, NFW3C_POOL_ID);
    }

    /**
     * @notice Fetches an array of DashboardStakes for the Pair Pool when ownership is split \
     * ie (EARTHLING/ROBOROVER) and NFW3C in pair pool have different owners.
     * @return dashboardStakes An array of DashboardStake structs
     * @param _address An Ethereum address
     */
    function getSplitStakes(address _address) public view returns (DashboardStake[] memory) {
        uint256 earthlingSplits = _getSplitStakeCount(nftContracts[EARTHLING_POOL_ID].balanceOf(_address), _address, EARTHLING_POOL_ID);
        uint256 roboroverSplits = _getSplitStakeCount(nftContracts[ROBOROVER_POOL_ID].balanceOf(_address), _address, ROBOROVER_POOL_ID);
        uint256 totalSplits = earthlingSplits + roboroverSplits;

        if(totalSplits == 0) {
            return new DashboardStake[](0);
        }

        DashboardStake[] memory earthlingSplitStakes = _getSplitStakes(earthlingSplits, _address, EARTHLING_POOL_ID);
        DashboardStake[] memory roboroverSplitStakes = _getSplitStakes(roboroverSplits, _address, ROBOROVER_POOL_ID);

        DashboardStake[] memory splitStakes = new DashboardStake[](totalSplits);
        uint256 offset = 0;
        for(uint256 i = 0; i < earthlingSplitStakes.length; ++i) {
            splitStakes[offset] = earthlingSplitStakes[i];
            ++offset;
        }

        for(uint256 i = 0; i < roboroverSplitStakes.length; ++i) {
            splitStakes[offset] = roboroverSplitStakes[i];
            ++offset;
        }

        return splitStakes;
    }

    function _getSplitStakes(uint256 splits, address _address, uint256 _mainPoolId) private view returns (DashboardStake[] memory) {

        DashboardStake[] memory dashboardStakes = new DashboardStake[](splits);
        uint256 counter;

        for(uint256 i = 0; i < nftContracts[_mainPoolId].balanceOf(_address); ++i) {
            uint256 mainTokenId = nftContracts[_mainPoolId].tokenOfOwnerByIndex(_address, i);
            if(mainToNfw3c[_mainPoolId][mainTokenId].isPaired) {
                uint256 nfw3cTokenId = mainToNfw3c[_mainPoolId][mainTokenId].tokenId;
                address currentOwner = nftContracts[NFW3C_POOL_ID].ownerOf(nfw3cTokenId);

                /* Split Pair Check*/
                if (currentOwner != _address) {
                    uint256 deposited = nftPosition[NFW3C_POOL_ID][nfw3cTokenId].stakedAmount;
                    uint256 unclaimed = deposited > 0 ? this.pendingRewards(NFW3C_POOL_ID, currentOwner, nfw3cTokenId) : 0;
                    uint256 rewards24Hrs = deposited > 0 ? _estimate24HourRewards(NFW3C_POOL_ID, currentOwner, nfw3cTokenId): 0;

                    DashboardPair memory pair = NULL_PAIR;
                    if(nfw3cToMain[nfw3cTokenId][_mainPoolId].isPaired) {
                        pair = DashboardPair(nfw3cToMain[nfw3cTokenId][_mainPoolId].tokenId, _mainPoolId);
                    }

                    DashboardStake memory dashboardStake = DashboardStake(NFW3C_POOL_ID, nfw3cTokenId, deposited, unclaimed, rewards24Hrs, pair);
                    dashboardStakes[counter] = dashboardStake;
                    ++counter;
                }
            }
        }

        return dashboardStakes;
    }

    function _getSplitStakeCount(uint256 nftCount, address _address, uint256 _mainPoolId) private view returns (uint256) {
        uint256 splitCount;
        for(uint256 i = 0; i < nftCount; ++i) {
            uint256 mainTokenId = nftContracts[_mainPoolId].tokenOfOwnerByIndex(_address, i);
            if(mainToNfw3c[_mainPoolId][mainTokenId].isPaired) {
                uint256 nfw3cTokenId = mainToNfw3c[_mainPoolId][mainTokenId].tokenId;
                address currentOwner = nftContracts[NFW3C_POOL_ID].ownerOf(nfw3cTokenId);
                if (currentOwner != _address) {
                    ++splitCount;
                }
            }
        }

        return splitCount;
    }

    function _getStakes(address _address, uint256 _poolId) private view returns (DashboardStake[] memory) {
        uint256 nftCount = nftContracts[_poolId].balanceOf(_address);
        DashboardStake[] memory dashboardStakes = nftCount > 0 ? new DashboardStake[](nftCount) : new DashboardStake[](0);

        if(nftCount == 0) {
            return dashboardStakes;
        }

        for(uint256 i = 0; i < nftCount; ++i) {
            uint256 tokenId = nftContracts[_poolId].tokenOfOwnerByIndex(_address, i);
            uint256 deposited = nftPosition[_poolId][tokenId].stakedAmount;
            uint256 unclaimed = deposited > 0 ? this.pendingRewards(_poolId, _address, tokenId) : 0;
            uint256 rewards24Hrs = deposited > 0 ? _estimate24HourRewards(_poolId, _address, tokenId): 0;

            DashboardPair memory pair = NULL_PAIR;
            if(_poolId == NFW3C_POOL_ID) {
                if(nfw3cToMain[tokenId][EARTHLING_POOL_ID].isPaired) {
                    pair = DashboardPair(nfw3cToMain[tokenId][EARTHLING_POOL_ID].tokenId, EARTHLING_POOL_ID);
                } else if(nfw3cToMain[tokenId][ROBOROVER_POOL_ID].isPaired) {
                    pair = DashboardPair(nfw3cToMain[tokenId][ROBOROVER_POOL_ID].tokenId, ROBOROVER_POOL_ID);
                }
            }

            DashboardStake memory dashboardStake = DashboardStake(_poolId, tokenId, deposited, unclaimed, rewards24Hrs, pair);
            dashboardStakes[i] = dashboardStake;
        }

        return dashboardStakes;
    }

    function _estimate24HourRewards(uint256 _poolId, address _address, uint256 _tokenId) private view returns (uint256) {
        Pool memory pool = pools[_poolId];
        Position memory position = _poolId == 0 ? addressPosition[_address]: nftPosition[_poolId][_tokenId];

        TimeRange memory rewards = getTimeRangeBy(_poolId, pool.lastRewardsRangeIndex);
        return (position.stakedAmount * uint256(rewards.rewardsPerHour) * 24) / uint256(pool.stakedAmount);
    }

    /**
     * @notice Fetches the current amount of claimable Nfte rewards for a given position from a given pool.
     * @return uint256 value of pending rewards
     * @param _poolId Available pool values 0-3
     * @param _address Address to lookup Position for
     * @param _tokenId An NFT id
     */
    function pendingRewards(uint256 _poolId, address _address, uint256 _tokenId) external view returns (uint256) {
        Pool memory pool = pools[_poolId];
        Position memory position = _poolId == 0 ? addressPosition[_address]: nftPosition[_poolId][_tokenId];

        (uint256 rewardsSinceLastCalculated,) = rewardsBy(_poolId, pool.lastRewardedTimestampHour, getPreviousTimestampHour());
        uint256 accumulatedRewardsPerShare = pool.accumulatedRewardsPerShare;

        if (block.timestamp > pool.lastRewardedTimestampHour + SECONDS_PER_HOUR && pool.stakedAmount != 0) {
            accumulatedRewardsPerShare = accumulatedRewardsPerShare + rewardsSinceLastCalculated * APE_COIN_PRECISION / pool.stakedAmount;
        }
        return ((position.stakedAmount * accumulatedRewardsPerShare).toInt256() - position.rewardsDebt).toUint256() / APE_COIN_PRECISION;
    }

    // Convenience methods for timestamp calculation

    /// @notice the minutes (0 to 59) of a timestamp
    function getMinute(uint256 timestamp) internal pure returns (uint256 minute) {
        uint256 secs = timestamp % SECONDS_PER_HOUR;
        minute = secs / SECONDS_PER_MINUTE;
    }

    /// @notice the seconds (0 to 59) of a timestamp
    function getSecond(uint256 timestamp) internal pure returns (uint256 second) {
        second = timestamp % SECONDS_PER_MINUTE;
    }

    /// @notice the previous whole hour of a timestamp
    function getPreviousTimestampHour() internal view returns (uint256) {
        return block.timestamp - (getMinute(block.timestamp) * 60 + getSecond(block.timestamp));
    }

    // Private Methods - shared logic
    function _deposit(uint256 _poolId, Position storage _position, uint256 _amount) private {
        Pool storage pool = pools[_poolId];

        _position.stakedAmount += _amount;
        pool.stakedAmount += _amount.toUint96();
        _position.rewardsDebt += (_amount * pool.accumulatedRewardsPerShare).toInt256();
    }

    function _depositNft(uint256 _poolId, SingleNft[] calldata _nfts) private {
        updatePool(_poolId);
        uint256 tokenId;
        uint256 amount;
        Position storage position;
        uint256 length = _nfts.length;
        uint256 totalDeposit;
        for(uint256 i; i < length;) {
            tokenId = _nfts[i].tokenId;
            position = nftPosition[_poolId][tokenId];
            if (position.stakedAmount == 0) {
                if (nftContracts[_poolId].ownerOf(tokenId) != msg.sender) revert CallerNotOwner();
            }
            amount = _nfts[i].amount;
            _depositNftGuard(_poolId, position, amount);
            totalDeposit += amount;
            emit DepositNft(msg.sender, _poolId, amount, tokenId);
            unchecked {
                ++i;
            }
        }
        if (totalDeposit > 0) nfte.transferFrom(msg.sender, address(this), totalDeposit);
    }

    function _depositPairNft(uint256 mainTypePoolId, PairNftDepositWithAmount[] calldata _nfts) private {
        uint256 length = _nfts.length;
        uint256 totalDeposit;
        PairNftDepositWithAmount memory pair;
        Position storage position;
        for(uint256 i; i < length;) {
            pair = _nfts[i];
            position = nftPosition[NFW3C_POOL_ID][pair.nfw3cTokenId];

            if(position.stakedAmount == 0) {
                if (nftContracts[mainTypePoolId].ownerOf(pair.mainTokenId) != msg.sender
                    || mainToNfw3c[mainTypePoolId][pair.mainTokenId].isPaired) revert MainTokenNotOwnedOrPaired();
                if (nftContracts[NFW3C_POOL_ID].ownerOf(pair.nfw3cTokenId) != msg.sender
                    || nfw3cToMain[pair.nfw3cTokenId][mainTypePoolId].isPaired) revert NFW3CNotOwnedOrPaired();

                mainToNfw3c[mainTypePoolId][pair.mainTokenId] = PairingStatus(pair.nfw3cTokenId, true);
                nfw3cToMain[pair.nfw3cTokenId][mainTypePoolId] = PairingStatus(pair.mainTokenId, true);
            } else if (pair.mainTokenId != nfw3cToMain[pair.nfw3cTokenId][mainTypePoolId].tokenId
                || pair.nfw3cTokenId != mainToNfw3c[mainTypePoolId][pair.mainTokenId].tokenId)
                    revert NFW3CAlreadyPaired();

            _depositNftGuard(NFW3C_POOL_ID, position, pair.amount);
            totalDeposit += pair.amount;
            emit DepositPairNft(msg.sender, pair.amount, mainTypePoolId, pair.mainTokenId, pair.nfw3cTokenId);
            unchecked {
                ++i;
            }
        }
        if (totalDeposit > 0) nfte.transferFrom(msg.sender, address(this), totalDeposit);
    }

    function _depositNftGuard(uint256 _poolId, Position storage _position, uint256 _amount) private {
        if (_amount < MIN_DEPOSIT) revert DepositMoreThanOneAPE();
        if (_amount + _position.stakedAmount > pools[_poolId].timeRanges[pools[_poolId].lastRewardsRangeIndex].capPerPosition)
            revert ExceededCapAmount();

        _deposit(_poolId, _position, _amount);
    }

    function _claim(uint256 _poolId, Position storage _position, address _recipient) private returns (uint256 rewardsToBeClaimed) {
        Pool storage pool = pools[_poolId];

        int256 accumulatedNftes = (_position.stakedAmount * uint256(pool.accumulatedRewardsPerShare)).toInt256();
        rewardsToBeClaimed = (accumulatedNftes - _position.rewardsDebt).toUint256() / APE_COIN_PRECISION;

        _position.rewardsDebt = accumulatedNftes;

        if (rewardsToBeClaimed != 0) {
            nfte.transfer(_recipient, rewardsToBeClaimed);
        }
    }

    function _claimNft(uint256 _poolId, uint256[] calldata _nfts, address _recipient) private {
        updatePool(_poolId);
        uint256 tokenId;
        uint256 rewardsToBeClaimed;
        uint256 length = _nfts.length;
        for(uint256 i; i < length;) {
            tokenId = _nfts[i];
            if (nftContracts[_poolId].ownerOf(tokenId) != msg.sender) revert CallerNotOwner();
            Position storage position = nftPosition[_poolId][tokenId];
            rewardsToBeClaimed = _claim(_poolId, position, _recipient);
            emit ClaimRewardsNft(msg.sender, _poolId, rewardsToBeClaimed, tokenId);
            unchecked {
                ++i;
            }
        }
    }

    function _claimPairNft(uint256 mainTypePoolId, PairNft[] calldata _pairs, address _recipient) private {
        uint256 length = _pairs.length;
        uint256 mainTokenId;
        uint256 nfw3cTokenId;
        Position storage position;
        PairingStatus storage mainToSecond;
        PairingStatus storage secondToMain;
        for(uint256 i; i < length;) {
            mainTokenId = _pairs[i].mainTokenId;
            if (nftContracts[mainTypePoolId].ownerOf(mainTokenId) != msg.sender) revert NotOwnerOfMain();

            nfw3cTokenId = _pairs[i].nfw3cTokenId;
            if (nftContracts[NFW3C_POOL_ID].ownerOf(nfw3cTokenId) != msg.sender) revert NotOwnerOfNFW3C();

            mainToSecond = mainToNfw3c[mainTypePoolId][mainTokenId];
            secondToMain = nfw3cToMain[nfw3cTokenId][mainTypePoolId];

            if (mainToSecond.tokenId != nfw3cTokenId || !mainToSecond.isPaired
                || secondToMain.tokenId != mainTokenId || !secondToMain.isPaired) revert ProvidedTokensNotPaired();

            position = nftPosition[NFW3C_POOL_ID][nfw3cTokenId];
            uint256 rewardsToBeClaimed = _claim(NFW3C_POOL_ID, position, _recipient);
            emit ClaimRewardsPairNft(msg.sender, rewardsToBeClaimed, mainTypePoolId, mainTokenId, nfw3cTokenId);
            unchecked {
                ++i;
            }
        }
    }

    function _withdraw(uint256 _poolId, Position storage _position, uint256 _amount) private {
        if (_amount > _position.stakedAmount) revert ExceededStakedAmount();

        Pool storage pool = pools[_poolId];

        _position.stakedAmount -= _amount;
        pool.stakedAmount -= _amount.toUint96();
        _position.rewardsDebt -= (_amount * pool.accumulatedRewardsPerShare).toInt256();
    }

    function _withdrawNft(uint256 _poolId, SingleNft[] calldata _nfts, address _recipient) private {
        updatePool(_poolId);
        uint256 tokenId;
        uint256 amount;
        uint256 length = _nfts.length;
        uint256 totalWithdraw;
        Position storage position;
        for(uint256 i; i < length;) {
            tokenId = _nfts[i].tokenId;
            if (nftContracts[_poolId].ownerOf(tokenId) != msg.sender) revert CallerNotOwner();

            amount = _nfts[i].amount;
            position = nftPosition[_poolId][tokenId];
            if (amount == position.stakedAmount) {
                uint256 rewardsToBeClaimed = _claim(_poolId, position, _recipient);
                emit ClaimRewardsNft(msg.sender, _poolId, rewardsToBeClaimed, tokenId);
            }
            _withdraw(_poolId, position, amount);
            totalWithdraw += amount;
            emit WithdrawNft(msg.sender, _poolId, amount, _recipient, tokenId);
            unchecked {
                ++i;
            }
        }
        if (totalWithdraw > 0) nfte.transfer(_recipient, totalWithdraw);
    }

    function _withdrawPairNft(uint256 mainTypePoolId, PairNftWithdrawWithAmount[] calldata _nfts) private {
        address mainTokenOwner;
        address nfw3cOwner;
        PairNftWithdrawWithAmount memory pair;
        PairingStatus storage mainToSecond;
        PairingStatus storage secondToMain;
        Position storage position;
        uint256 length = _nfts.length;
        for(uint256 i; i < length;) {
            pair = _nfts[i];
            mainTokenOwner = nftContracts[mainTypePoolId].ownerOf(pair.mainTokenId);
            nfw3cOwner = nftContracts[NFW3C_POOL_ID].ownerOf(pair.nfw3cTokenId);

            if (mainTokenOwner != msg.sender) {
                if (nfw3cOwner != msg.sender) revert NeitherTokenInPairOwnedByCaller();
            }

            mainToSecond = mainToNfw3c[mainTypePoolId][pair.mainTokenId];
            secondToMain = nfw3cToMain[pair.nfw3cTokenId][mainTypePoolId];

            if (mainToSecond.tokenId != pair.nfw3cTokenId || !mainToSecond.isPaired
                || secondToMain.tokenId != pair.mainTokenId || !secondToMain.isPaired) revert ProvidedTokensNotPaired();

            position = nftPosition[NFW3C_POOL_ID][pair.nfw3cTokenId];
            if(!pair.isUncommit) {
                if(pair.amount == position.stakedAmount) revert UncommitWrongParameters();
            }
            if (mainTokenOwner != nfw3cOwner) {
                if (!pair.isUncommit) revert SplitPairCantPartiallyWithdraw();
            }

            if (pair.isUncommit) {
                uint256 rewardsToBeClaimed = _claim(NFW3C_POOL_ID, position, nfw3cOwner);
                mainToNfw3c[mainTypePoolId][pair.mainTokenId] = PairingStatus(0, false);
                nfw3cToMain[pair.nfw3cTokenId][mainTypePoolId] = PairingStatus(0, false);
                emit ClaimRewardsPairNft(msg.sender, rewardsToBeClaimed, mainTypePoolId, pair.mainTokenId, pair.nfw3cTokenId);
            }
            uint256 finalAmountToWithdraw = pair.isUncommit ? position.stakedAmount: pair.amount;
            _withdraw(NFW3C_POOL_ID, position, finalAmountToWithdraw);
            nfte.transfer(mainTokenOwner, finalAmountToWithdraw);
            emit WithdrawPairNft(msg.sender, finalAmountToWithdraw, mainTypePoolId, pair.mainTokenId, pair.nfw3cTokenId);
            unchecked {
                ++i;
            }
        }
    }

}
