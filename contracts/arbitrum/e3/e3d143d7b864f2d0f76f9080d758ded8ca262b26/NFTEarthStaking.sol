//SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

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
 * @title NFTEarthStaking Contract
 * @notice Stake NfteToken across four different pools that release hourly rewards

 */
contract NFTEarthStaking is Ownable {

    using SafeCast for uint256;
    using SafeCast for int256;

    /// @notice State for NfteToken, EARTHLINGS, ROBOROVERS, and Pair Pools
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

    /// @dev Struct for depositing and withdrawing from the EARTHLINGS and ROBOROVERS NFT pools
    struct SingleNft {
        uint32 tokenId;
        uint224 amount;
    }
    /// @dev Struct for depositing from the NFW3C (Pair) pool
    struct PairNftDepositWithAmount {
        uint32 mainTokenId;
        uint32 NFW3CTokenId;
        uint184 amount;
    }
    /// @dev Struct for withdrawing from the NFW3C (Pair) pool
    struct PairNftWithdrawWithAmount {
        uint32 mainTokenId;
        uint32 NFW3CTokenId;
        uint184 amount;
        bool isUncommit;
    }
    /// @dev Struct for claiming from an NFT pool
    struct PairNft {
        uint128 mainTokenId;
        uint128 NFW3CTokenId;
    }
    /// @dev NFT paired status.  Can be used bi-directionally (EARTHLINGS/ROBOROVERS -> NFW3C) or (NFW3C -> EARTHLINGS/ROBOROVERS)
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
    /// @dev Placeholder for pair status, used by NfteToken Pool
    DashboardPair private NULL_PAIR = DashboardPair(0, 0);

    /// @notice Internal NfteToken amount for distributing staking reward claims
    IERC20 public immutable NfteToken;
    uint256 private constant NFTE_TOKEN_PRECISION = 1e18;
    uint256 private constant MIN_DEPOSIT = 1 * NFTE_TOKEN_PRECISION;
    uint256 private constant SECONDS_PER_HOUR = 3600;
    uint256 private constant SECONDS_PER_MINUTE = 60;

    uint256 constant NfteToken_POOL_ID = 0;
    uint256 constant EARTHLINGS_POOL_ID = 1;
    uint256 constant ROBOROVERS_POOL_ID = 2;
    uint256 constant NFW3C_POOL_ID = 3;
    Pool[4] public pools;

    /// @dev NFT contract mapping per pool
    mapping(uint256 => ERC721Enumerable) public nftContracts;
    /// @dev poolId => tokenId => nft position
    mapping(uint256 => mapping(uint256 => Position)) public nftPosition;
    /// @dev main type pool ID: 1: EARTHLINGS 2: ROBOROVERS => main token ID => NFW3C token ID
    mapping(uint256 => mapping(uint256 => PairingStatus)) public mainToNFW3C;
    /// @dev NFW3C Token ID => main type pool ID: 1: EARTHLINGS 2: ROBOROVERS => main token ID
    mapping(uint256 => mapping(uint256 => PairingStatus)) public NFW3CToMain;

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
        uint256 NFW3CTokenId
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
        uint256 NFW3CTokenId
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
        uint256 NFW3CTokenId
    );

    error DepositMoreThanOneNFTE();
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
     * @notice Construct a new NFTEarthStaking instance
     * @param _NfteTokenContractAddress The NfteToken ERC20 contract address
     * @param _EARTHLINGSContractAddress The EARTHLINGS NFT contract address
     * @param _ROBOROVERSContractAddress The ROBOROVERS NFT contract address
     * @param _NFW3CContractAddress The NFW3C NFT contract address
     */
    constructor(
        address _NfteTokenContractAddress,
        address _EARTHLINGSContractAddress,
        address _ROBOROVERSContractAddress,
        address _NFW3CContractAddress
    ) {
        NfteToken = IERC20(_NfteTokenContractAddress);
        nftContracts[EARTHLINGS_POOL_ID] = ERC721Enumerable(_EARTHLINGSContractAddress);
        nftContracts[ROBOROVERS_POOL_ID] = ERC721Enumerable(_ROBOROVERSContractAddress);
        nftContracts[NFW3C_POOL_ID] = ERC721Enumerable(_NFW3CContractAddress);
    }

    // Deposit/Commit Methods

    /**
     * @notice Deposit NfteToken to the NfteToken Pool
     * @param _amount Amount in NfteToken
     * @param _recipient Address the deposit it stored to
     * @dev NfteToken deposit must be >= 1 NfteToken
     */
    function depositNfteToken(uint256 _amount, address _recipient) public {
        if (_amount < MIN_DEPOSIT) revert DepositMoreThanOneNFTE();
        updatePool(NfteToken_POOL_ID);

        Position storage position = addressPosition[_recipient];
        _deposit(NfteToken_POOL_ID, position, _amount);

        NfteToken.transferFrom(msg.sender, address(this), _amount);

        emit Deposit(msg.sender, _amount, _recipient);
    }

    /**
     * @notice Deposit NfteToken to the NfteToken Pool
     * @param _amount Amount in NfteToken
     * @dev Deposit on behalf of msg.sender. NfteToken deposit must be >= 1 NfteToken
     */
    function depositSelfNfteToken(uint256 _amount) external {
        depositNfteToken(_amount, msg.sender);
    }

    /**
     * @notice Deposit NfteToken to the EARTHLINGS Pool
     * @param _nfts Array of SingleNft structs
     * @dev Commits 1 or more EARTHLINGS NFTs, each with an NfteToken amount to the EARTHLINGS pool.\
     * Each EARTHLINGS committed must attach an NfteToken amount >= 1 NfteToken and <= the EARTHLINGS pool cap amount.
     */
    function depositEARTHLINGS(SingleNft[] calldata _nfts) external {
        _depositNft(EARTHLINGS_POOL_ID, _nfts);
    }

    /**
     * @notice Deposit NfteToken to the ROBOROVERS Pool
     * @param _nfts Array of SingleNft structs
     * @dev Commits 1 or more ROBOROVERS NFTs, each with an NfteToken amount to the ROBOROVERS pool.\
     * Each ROBOROVERS committed must attach an NfteToken amount >= 1 NfteToken and <= the ROBOROVERS pool cap amount.
     */
    function depositROBOROVERS(SingleNft[] calldata _nfts) external {
        _depositNft(ROBOROVERS_POOL_ID, _nfts);
    }

    /**
     * @notice Deposit NfteToken to the Pair Pool, where Pair = (EARTHLINGS + NFW3C) or (ROBOROVERS + NFW3C)
     * @param _EARTHLINGSPairs Array of PairNftDepositWithAmount structs
     * @param _ROBOROVERSPairs Array of PairNftDepositWithAmount structs
     * @dev Commits 1 or more Pairs, each with an NfteToken amount to the Pair pool.\
     * Each NFW3C committed must attach an NfteToken amount >= 1 NfteToken and <= the Pair pool cap amount.\
     * Example 1: EARTHLINGS + NFW3C + 1 NfteToken:  [[0, 0, "1000000000000000000"],[]]\
     * Example 2: ROBOROVERS + NFW3C + 1 NfteToken:  [[], [0, 0, "1000000000000000000"]]\
     * Example 3: (EARTHLINGS + NFW3C + 1 NfteToken) and (ROBOROVERS + NFW3C + 1 NfteToken): [[0, 0, "1000000000000000000"], [0, 1, "1000000000000000000"]]
     */
    function depositNFW3C(PairNftDepositWithAmount[] calldata _EARTHLINGSPairs, PairNftDepositWithAmount[] calldata _ROBOROVERSPairs) external {
        updatePool(NFW3C_POOL_ID);
        _depositPairNft(EARTHLINGS_POOL_ID, _EARTHLINGSPairs);
        _depositPairNft(ROBOROVERS_POOL_ID, _ROBOROVERSPairs);
    }

    // Claim Rewards Methods

    /**
     * @notice Claim rewards for msg.sender and send to recipient
     * @param _recipient Address to send claim reward to
     */
    function claimNfteToken(address _recipient) public {
        updatePool(NfteToken_POOL_ID);

        Position storage position = addressPosition[msg.sender];
        uint256 rewardsToBeClaimed = _claim(NfteToken_POOL_ID, position, _recipient);

        emit ClaimRewards(msg.sender, rewardsToBeClaimed, _recipient);
    }

    /// @notice Claim and send rewards
    function claimSelfNfteToken() external {
        claimNfteToken(msg.sender);
    }

    /**
     * @notice Claim rewards for array of EARTHLINGS NFTs and send to recipient
     * @param _nfts Array of NFTs owned and committed by the msg.sender
     * @param _recipient Address to send claim reward to
     */
    function claimEARTHLINGS(uint256[] calldata _nfts, address _recipient) external {
        _claimNft(EARTHLINGS_POOL_ID, _nfts, _recipient);
    }

    /**
     * @notice Claim rewards for array of EARTHLINGS NFTs
     * @param _nfts Array of NFTs owned and committed by the msg.sender
     */
    function claimSelfEARTHLINGS(uint256[] calldata _nfts) external {
        _claimNft(EARTHLINGS_POOL_ID, _nfts, msg.sender);
    }

    /**
     * @notice Claim rewards for array of ROBOROVERS NFTs and send to recipient
     * @param _nfts Array of NFTs owned and committed by the msg.sender
     * @param _recipient Address to send claim reward to
     */
    function claimROBOROVERS(uint256[] calldata _nfts, address _recipient) external {
        _claimNft(ROBOROVERS_POOL_ID, _nfts, _recipient);
    }

    /**
     * @notice Claim rewards for array of ROBOROVERS NFTs
     * @param _nfts Array of NFTs owned and committed by the msg.sender
     */
    function claimSelfROBOROVERS(uint256[] calldata _nfts) external {
        _claimNft(ROBOROVERS_POOL_ID, _nfts, msg.sender);
    }

    /**
     * @notice Claim rewards for array of Paired NFTs and send to recipient
     * @param _EARTHLINGSPairs Array of Paired EARTHLINGS NFTs owned and committed by the msg.sender
     * @param _ROBOROVERSPairs Array of Paired ROBOROVERS NFTs owned and committed by the msg.sender
     * @param _recipient Address to send claim reward to
     */
    function claimNFW3C(PairNft[] calldata _EARTHLINGSPairs, PairNft[] calldata _ROBOROVERSPairs, address _recipient) public {
        updatePool(NFW3C_POOL_ID);
        _claimPairNft(EARTHLINGS_POOL_ID, _EARTHLINGSPairs, _recipient);
        _claimPairNft(ROBOROVERS_POOL_ID, _ROBOROVERSPairs, _recipient);
    }

    /**
     * @notice Claim rewards for array of Paired NFTs
     * @param _EARTHLINGSPairs Array of Paired EARTHLINGS NFTs owned and committed by the msg.sender
     * @param _ROBOROVERSPairs Array of Paired ROBOROVERS NFTs owned and committed by the msg.sender
     */
    function claimSelfNFW3C(PairNft[] calldata _EARTHLINGSPairs, PairNft[] calldata _ROBOROVERSPairs) external {
        claimNFW3C(_EARTHLINGSPairs, _ROBOROVERSPairs, msg.sender);
    }

    // Uncommit/Withdraw Methods

    /**
     * @notice Withdraw staked NfteToken from the NfteToken pool.  Performs an automatic claim as part of the withdraw process.
     * @param _amount Amount of NfteToken
     * @param _recipient Address to send withdraw amount and claim to
     */
    function withdrawNfteToken(uint256 _amount, address _recipient) public {
        updatePool(NfteToken_POOL_ID);

        Position storage position = addressPosition[msg.sender];
        if (_amount == position.stakedAmount) {
            uint256 rewardsToBeClaimed = _claim(NfteToken_POOL_ID, position, _recipient);
            emit ClaimRewards(msg.sender, rewardsToBeClaimed, _recipient);
        }
        _withdraw(NfteToken_POOL_ID, position, _amount);

        NfteToken.transfer(_recipient, _amount);

        emit Withdraw(msg.sender, _amount, _recipient);
    }

    /**
     * @notice Withdraw staked NfteToken from the NfteToken pool.  If withdraw is total staked amount, performs an automatic claim.
     * @param _amount Amount of NfteToken
     */
    function withdrawSelfNfteToken(uint256 _amount) external {
        withdrawNfteToken(_amount, msg.sender);
    }

    /**
     * @notice Withdraw staked NfteToken from the EARTHLINGS pool.  If withdraw is total staked amount, performs an automatic claim.
     * @param _nfts Array of EARTHLINGS NFT's with staked amounts
     * @param _recipient Address to send withdraw amount and claim to
     */
    function withdrawEARTHLINGS(SingleNft[] calldata _nfts, address _recipient) external {
        _withdrawNft(EARTHLINGS_POOL_ID, _nfts, _recipient);
    }

    /**
     * @notice Withdraw staked NfteToken from the EARTHLINGS pool.  If withdraw is total staked amount, performs an automatic claim.
     * @param _nfts Array of EARTHLINGS NFT's with staked amounts
     */
    function withdrawSelfEARTHLINGS(SingleNft[] calldata _nfts) external {
        _withdrawNft(EARTHLINGS_POOL_ID, _nfts, msg.sender);
    }

    /**
     * @notice Withdraw staked NfteToken from the ROBOROVERS pool.  If withdraw is total staked amount, performs an automatic claim.
     * @param _nfts Array of ROBOROVERS NFT's with staked amounts
     * @param _recipient Address to send withdraw amount and claim to
     */
    function withdrawROBOROVERS(SingleNft[] calldata _nfts, address _recipient) external {
        _withdrawNft(ROBOROVERS_POOL_ID, _nfts, _recipient);
    }

    /**
     * @notice Withdraw staked NfteToken from the ROBOROVERS pool.  If withdraw is total staked amount, performs an automatic claim.
     * @param _nfts Array of ROBOROVERS NFT's with staked amounts
     */
    function withdrawSelfROBOROVERS(SingleNft[] calldata _nfts) external {
        _withdrawNft(ROBOROVERS_POOL_ID, _nfts, msg.sender);
    }

    /**
     * @notice Withdraw staked NfteToken from the Pair pool.  If withdraw is total staked amount, performs an automatic claim.
     * @param _EARTHLINGSPairs Array of Paired EARTHLINGS NFT's with staked amounts and isUncommit boolean
     * @param _ROBOROVERSPairs Array of Paired ROBOROVERS NFT's with staked amounts and isUncommit boolean
     * @dev if pairs have split ownership and NFW3C is attempting a withdraw, the withdraw must be for the total staked amount
     */
    function withdrawNFW3C(PairNftWithdrawWithAmount[] calldata _EARTHLINGSPairs, PairNftWithdrawWithAmount[] calldata _ROBOROVERSPairs) external {
        updatePool(NFW3C_POOL_ID);
        _withdrawPairNft(EARTHLINGS_POOL_ID, _EARTHLINGSPairs);
        _withdrawPairNft(ROBOROVERS_POOL_ID, _ROBOROVERSPairs);
    }

    // Time Range Methods

    /**
     * @notice Add single time range with a given rewards per hour for a given pool
     * @dev In practice one Time Range will represent one quarter (defined by `_startTimestamp`and `_endTimeStamp` as whole hours)
     * where the rewards per hour is constant for a given pool.
     * @param _poolId Available pool values 0-3
     * @param _amount Total amount of NfteToken to be distributed over the range
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
     * @return uint256 The amount of NfteToken rewards to be distributed by pool for a given time range
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
        pool.accumulatedRewardsPerShare = (pool.accumulatedRewardsPerShare + (rewards * NFTE_TOKEN_PRECISION) / pool.stakedAmount).toUint96();
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
     * @return PoolUI for NfteToken.
     * @return PoolUI for EARTHLINGS.
     * @return PoolUI for ROBOROVERS.
     * @return PoolUI for NFW3C.
     */
    function getPoolsUI() public view returns (PoolUI memory, PoolUI memory, PoolUI memory, PoolUI memory) {
        Pool memory NfteTokenPool = pools[0];
        Pool memory EARTHLINGSPool = pools[1];
        Pool memory ROBOROVERSPool = pools[2];
        Pool memory NFW3CPool = pools[3];
        uint256 current = getCurrentTimeRangeIndex(NfteTokenPool);
        return (PoolUI(0,NfteTokenPool.stakedAmount, NfteTokenPool.timeRanges[current]),
                PoolUI(1,EARTHLINGSPool.stakedAmount, EARTHLINGSPool.timeRanges[current]),
                PoolUI(2,ROBOROVERSPool.stakedAmount, ROBOROVERSPool.timeRanges[current]),
                PoolUI(3,NFW3CPool.stakedAmount, NFW3CPool.timeRanges[current]));
    }

    /**
     * @notice Fetches an address total staked amount, used by voting contract
     * @return amount uint256 staked amount for all pools.
     * @param _address An Ethereum address
     */
    function stakedTotal(address _address) external view returns (uint256) {
        uint256 total = addressPosition[_address].stakedAmount;

        total += _stakedTotal(EARTHLINGS_POOL_ID, _address);
        total += _stakedTotal(ROBOROVERS_POOL_ID, _address);
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

        uint256 nftCount = nftContracts[EARTHLINGS_POOL_ID].balanceOf(_addr);
        for(uint256 i = 0; i < nftCount; ++i) {
            uint256 EARTHLINGSTokenId = nftContracts[EARTHLINGS_POOL_ID].tokenOfOwnerByIndex(_addr, i);
            if (mainToNFW3C[EARTHLINGS_POOL_ID][EARTHLINGSTokenId].isPaired) {
                uint256 NFW3CTokenId = mainToNFW3C[EARTHLINGS_POOL_ID][EARTHLINGSTokenId].tokenId;
                total += nftPosition[NFW3C_POOL_ID][NFW3CTokenId].stakedAmount;
            }
        }

        nftCount = nftContracts[ROBOROVERS_POOL_ID].balanceOf(_addr);
        for(uint256 i = 0; i < nftCount; ++i) {
            uint256 ROBOROVERSTokenId = nftContracts[ROBOROVERS_POOL_ID].tokenOfOwnerByIndex(_addr, i);
            if (mainToNFW3C[ROBOROVERS_POOL_ID][ROBOROVERSTokenId].isPaired) {
                uint256 NFW3CTokenId = mainToNFW3C[ROBOROVERS_POOL_ID][ROBOROVERSTokenId].tokenId;
                total += nftPosition[NFW3C_POOL_ID][NFW3CTokenId].stakedAmount;
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

        DashboardStake memory NfteTokenStake = getNfteTokenStake(_address);
        DashboardStake[] memory EARTHLINGSStakes = getEARTHLINGSStakes(_address);
        DashboardStake[] memory ROBOROVERSStakes = getROBOROVERSStakes(_address);
        DashboardStake[] memory NFW3CStakes = getNFW3CStakes(_address);
        DashboardStake[] memory splitStakes = getSplitStakes(_address);

        uint256 count = (EARTHLINGSStakes.length + ROBOROVERSStakes.length + NFW3CStakes.length + splitStakes.length + 1);
        DashboardStake[] memory allStakes = new DashboardStake[](count);

        uint256 offset = 0;
        allStakes[offset] = NfteTokenStake;
        ++offset;

        for(uint256 i = 0; i < EARTHLINGSStakes.length; ++i) {
            allStakes[offset] = EARTHLINGSStakes[i];
            ++offset;
        }

        for(uint256 i = 0; i < ROBOROVERSStakes.length; ++i) {
            allStakes[offset] = ROBOROVERSStakes[i];
            ++offset;
        }

        for(uint256 i = 0; i < NFW3CStakes.length; ++i) {
            allStakes[offset] = NFW3CStakes[i];
            ++offset;
        }

        for(uint256 i = 0; i < splitStakes.length; ++i) {
            allStakes[offset] = splitStakes[i];
            ++offset;
        }

        return allStakes;
    }

    /**
     * @notice Fetches a DashboardStake for the NfteToken pool
     * @return dashboardStake A dashboardStake struct
     * @param _address An Ethereum address
     */
    function getNfteTokenStake(address _address) public view returns (DashboardStake memory) {
        uint256 tokenId = 0;
        uint256 deposited = addressPosition[_address].stakedAmount;
        uint256 unclaimed = deposited > 0 ? this.pendingRewards(0, _address, tokenId) : 0;
        uint256 rewards24Hrs = deposited > 0 ? _estimate24HourRewards(0, _address, 0) : 0;

        return DashboardStake(NfteToken_POOL_ID, tokenId, deposited, unclaimed, rewards24Hrs, NULL_PAIR);
    }

    /**
     * @notice Fetches an array of DashboardStakes for the EARTHLINGS pool
     * @return dashboardStakes An array of DashboardStake structs
     */
    function getEARTHLINGSStakes(address _address) public view returns (DashboardStake[] memory) {
        return _getStakes(_address, EARTHLINGS_POOL_ID);
    }

    /**
     * @notice Fetches an array of DashboardStakes for the ROBOROVERS pool
     * @return dashboardStakes An array of DashboardStake structs
     */
    function getROBOROVERSStakes(address _address) public view returns (DashboardStake[] memory) {
        return _getStakes(_address, ROBOROVERS_POOL_ID);
    }

    /**
     * @notice Fetches an array of DashboardStakes for the NFW3C pool
     * @return dashboardStakes An array of DashboardStake structs
     */
    function getNFW3CStakes(address _address) public view returns (DashboardStake[] memory) {
        return _getStakes(_address, NFW3C_POOL_ID);
    }

    /**
     * @notice Fetches an array of DashboardStakes for the Pair Pool when ownership is split \
     * ie (EARTHLINGS/ROBOROVERS) and NFW3C in pair pool have different owners.
     * @return dashboardStakes An array of DashboardStake structs
     * @param _address An Ethereum address
     */
    function getSplitStakes(address _address) public view returns (DashboardStake[] memory) {
        uint256 EARTHLINGSSplits = _getSplitStakeCount(nftContracts[EARTHLINGS_POOL_ID].balanceOf(_address), _address, EARTHLINGS_POOL_ID);
        uint256 ROBOROVERSSplits = _getSplitStakeCount(nftContracts[ROBOROVERS_POOL_ID].balanceOf(_address), _address, ROBOROVERS_POOL_ID);
        uint256 totalSplits = EARTHLINGSSplits + ROBOROVERSSplits;

        if(totalSplits == 0) {
            return new DashboardStake[](0);
        }

        DashboardStake[] memory EARTHLINGSSplitStakes = _getSplitStakes(EARTHLINGSSplits, _address, EARTHLINGS_POOL_ID);
        DashboardStake[] memory ROBOROVERSSplitStakes = _getSplitStakes(ROBOROVERSSplits, _address, ROBOROVERS_POOL_ID);

        DashboardStake[] memory splitStakes = new DashboardStake[](totalSplits);
        uint256 offset = 0;
        for(uint256 i = 0; i < EARTHLINGSSplitStakes.length; ++i) {
            splitStakes[offset] = EARTHLINGSSplitStakes[i];
            ++offset;
        }

        for(uint256 i = 0; i < ROBOROVERSSplitStakes.length; ++i) {
            splitStakes[offset] = ROBOROVERSSplitStakes[i];
            ++offset;
        }

        return splitStakes;
    }

    function _getSplitStakes(uint256 splits, address _address, uint256 _mainPoolId) private view returns (DashboardStake[] memory) {

        DashboardStake[] memory dashboardStakes = new DashboardStake[](splits);
        uint256 counter;

        for(uint256 i = 0; i < nftContracts[_mainPoolId].balanceOf(_address); ++i) {
            uint256 mainTokenId = nftContracts[_mainPoolId].tokenOfOwnerByIndex(_address, i);
            if(mainToNFW3C[_mainPoolId][mainTokenId].isPaired) {
                uint256 NFW3CTokenId = mainToNFW3C[_mainPoolId][mainTokenId].tokenId;
                address currentOwner = nftContracts[NFW3C_POOL_ID].ownerOf(NFW3CTokenId);

                /* Split Pair Check*/
                if (currentOwner != _address) {
                    uint256 deposited = nftPosition[NFW3C_POOL_ID][NFW3CTokenId].stakedAmount;
                    uint256 unclaimed = deposited > 0 ? this.pendingRewards(NFW3C_POOL_ID, currentOwner, NFW3CTokenId) : 0;
                    uint256 rewards24Hrs = deposited > 0 ? _estimate24HourRewards(NFW3C_POOL_ID, currentOwner, NFW3CTokenId): 0;

                    DashboardPair memory pair = NULL_PAIR;
                    if(NFW3CToMain[NFW3CTokenId][_mainPoolId].isPaired) {
                        pair = DashboardPair(NFW3CToMain[NFW3CTokenId][_mainPoolId].tokenId, _mainPoolId);
                    }

                    DashboardStake memory dashboardStake = DashboardStake(NFW3C_POOL_ID, NFW3CTokenId, deposited, unclaimed, rewards24Hrs, pair);
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
            if(mainToNFW3C[_mainPoolId][mainTokenId].isPaired) {
                uint256 NFW3CTokenId = mainToNFW3C[_mainPoolId][mainTokenId].tokenId;
                address currentOwner = nftContracts[NFW3C_POOL_ID].ownerOf(NFW3CTokenId);
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
                if(NFW3CToMain[tokenId][EARTHLINGS_POOL_ID].isPaired) {
                    pair = DashboardPair(NFW3CToMain[tokenId][EARTHLINGS_POOL_ID].tokenId, EARTHLINGS_POOL_ID);
                } else if(NFW3CToMain[tokenId][ROBOROVERS_POOL_ID].isPaired) {
                    pair = DashboardPair(NFW3CToMain[tokenId][ROBOROVERS_POOL_ID].tokenId, ROBOROVERS_POOL_ID);
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
     * @notice Fetches the current amount of claimable NfteToken rewards for a given position from a given pool.
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
            accumulatedRewardsPerShare = accumulatedRewardsPerShare + rewardsSinceLastCalculated * NFTE_TOKEN_PRECISION / pool.stakedAmount;
        }
        return ((position.stakedAmount * accumulatedRewardsPerShare).toInt256() - position.rewardsDebt).toUint256() / NFTE_TOKEN_PRECISION;
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
        if (totalDeposit > 0) NfteToken.transferFrom(msg.sender, address(this), totalDeposit);
    }

    function _depositPairNft(uint256 mainTypePoolId, PairNftDepositWithAmount[] calldata _nfts) private {
        uint256 length = _nfts.length;
        uint256 totalDeposit;
        PairNftDepositWithAmount memory pair;
        Position storage position;
        for(uint256 i; i < length;) {
            pair = _nfts[i];
            position = nftPosition[NFW3C_POOL_ID][pair.NFW3CTokenId];

            if(position.stakedAmount == 0) {
                if (nftContracts[mainTypePoolId].ownerOf(pair.mainTokenId) != msg.sender
                    || mainToNFW3C[mainTypePoolId][pair.mainTokenId].isPaired) revert MainTokenNotOwnedOrPaired();
                if (nftContracts[NFW3C_POOL_ID].ownerOf(pair.NFW3CTokenId) != msg.sender
                    || NFW3CToMain[pair.NFW3CTokenId][mainTypePoolId].isPaired) revert NFW3CNotOwnedOrPaired();

                mainToNFW3C[mainTypePoolId][pair.mainTokenId] = PairingStatus(pair.NFW3CTokenId, true);
                NFW3CToMain[pair.NFW3CTokenId][mainTypePoolId] = PairingStatus(pair.mainTokenId, true);
            } else if (pair.mainTokenId != NFW3CToMain[pair.NFW3CTokenId][mainTypePoolId].tokenId
                || pair.NFW3CTokenId != mainToNFW3C[mainTypePoolId][pair.mainTokenId].tokenId)
                    revert NFW3CAlreadyPaired();

            _depositNftGuard(NFW3C_POOL_ID, position, pair.amount);
            totalDeposit += pair.amount;
            emit DepositPairNft(msg.sender, pair.amount, mainTypePoolId, pair.mainTokenId, pair.NFW3CTokenId);
            unchecked {
                ++i;
            }
        }
        if (totalDeposit > 0) NfteToken.transferFrom(msg.sender, address(this), totalDeposit);
    }

    function _depositNftGuard(uint256 _poolId, Position storage _position, uint256 _amount) private {
        if (_amount < MIN_DEPOSIT) revert DepositMoreThanOneNFTE();
        if (_amount + _position.stakedAmount > pools[_poolId].timeRanges[pools[_poolId].lastRewardsRangeIndex].capPerPosition)
            revert ExceededCapAmount();

        _deposit(_poolId, _position, _amount);
    }

    function _claim(uint256 _poolId, Position storage _position, address _recipient) private returns (uint256 rewardsToBeClaimed) {
        Pool storage pool = pools[_poolId];

        int256 accumulatedNfteTokens = (_position.stakedAmount * uint256(pool.accumulatedRewardsPerShare)).toInt256();
        rewardsToBeClaimed = (accumulatedNfteTokens - _position.rewardsDebt).toUint256() / NFTE_TOKEN_PRECISION;

        _position.rewardsDebt = accumulatedNfteTokens;

        if (rewardsToBeClaimed != 0) {
            NfteToken.transfer(_recipient, rewardsToBeClaimed);
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
        uint256 NFW3CTokenId;
        Position storage position;
        PairingStatus storage mainToSecond;
        PairingStatus storage secondToMain;
        for(uint256 i; i < length;) {
            mainTokenId = _pairs[i].mainTokenId;
            if (nftContracts[mainTypePoolId].ownerOf(mainTokenId) != msg.sender) revert NotOwnerOfMain();

            NFW3CTokenId = _pairs[i].NFW3CTokenId;
            if (nftContracts[NFW3C_POOL_ID].ownerOf(NFW3CTokenId) != msg.sender) revert NotOwnerOfNFW3C();

            mainToSecond = mainToNFW3C[mainTypePoolId][mainTokenId];
            secondToMain = NFW3CToMain[NFW3CTokenId][mainTypePoolId];

            if (mainToSecond.tokenId != NFW3CTokenId || !mainToSecond.isPaired
                || secondToMain.tokenId != mainTokenId || !secondToMain.isPaired) revert ProvidedTokensNotPaired();

            position = nftPosition[NFW3C_POOL_ID][NFW3CTokenId];
            uint256 rewardsToBeClaimed = _claim(NFW3C_POOL_ID, position, _recipient);
            emit ClaimRewardsPairNft(msg.sender, rewardsToBeClaimed, mainTypePoolId, mainTokenId, NFW3CTokenId);
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
        if (totalWithdraw > 0) NfteToken.transfer(_recipient, totalWithdraw);
    }

    function _withdrawPairNft(uint256 mainTypePoolId, PairNftWithdrawWithAmount[] calldata _nfts) private {
        address mainTokenOwner;
        address NFW3COwner;
        PairNftWithdrawWithAmount memory pair;
        PairingStatus storage mainToSecond;
        PairingStatus storage secondToMain;
        Position storage position;
        uint256 length = _nfts.length;
        for(uint256 i; i < length;) {
            pair = _nfts[i];
            mainTokenOwner = nftContracts[mainTypePoolId].ownerOf(pair.mainTokenId);
            NFW3COwner = nftContracts[NFW3C_POOL_ID].ownerOf(pair.NFW3CTokenId);

            if (mainTokenOwner != msg.sender) {
                if (NFW3COwner != msg.sender) revert NeitherTokenInPairOwnedByCaller();
            }

            mainToSecond = mainToNFW3C[mainTypePoolId][pair.mainTokenId];
            secondToMain = NFW3CToMain[pair.NFW3CTokenId][mainTypePoolId];

            if (mainToSecond.tokenId != pair.NFW3CTokenId || !mainToSecond.isPaired
                || secondToMain.tokenId != pair.mainTokenId || !secondToMain.isPaired) revert ProvidedTokensNotPaired();

            position = nftPosition[NFW3C_POOL_ID][pair.NFW3CTokenId];
            if(!pair.isUncommit) {
                if(pair.amount == position.stakedAmount) revert UncommitWrongParameters();
            }
            if (mainTokenOwner != NFW3COwner) {
                if (!pair.isUncommit) revert SplitPairCantPartiallyWithdraw();
            }

            if (pair.isUncommit) {
                uint256 rewardsToBeClaimed = _claim(NFW3C_POOL_ID, position, NFW3COwner);
                mainToNFW3C[mainTypePoolId][pair.mainTokenId] = PairingStatus(0, false);
                NFW3CToMain[pair.NFW3CTokenId][mainTypePoolId] = PairingStatus(0, false);
                emit ClaimRewardsPairNft(msg.sender, rewardsToBeClaimed, mainTypePoolId, pair.mainTokenId, pair.NFW3CTokenId);
            }
            uint256 finalAmountToWithdraw = pair.isUncommit ? position.stakedAmount: pair.amount;
            _withdraw(NFW3C_POOL_ID, position, finalAmountToWithdraw);
            NfteToken.transfer(mainTokenOwner, finalAmountToWithdraw);
            emit WithdrawPairNft(msg.sender, finalAmountToWithdraw, mainTypePoolId, pair.mainTokenId, pair.NFW3CTokenId);
            unchecked {
                ++i;
            }
        }
    }

}
