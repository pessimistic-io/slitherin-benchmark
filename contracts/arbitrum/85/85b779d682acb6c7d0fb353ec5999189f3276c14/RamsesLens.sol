// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./IPairFactory.sol";
import "./IVoter.sol";
import "./IVotingEscrow.sol";
import "./IMinter.sol";
import "./IPair.sol";
import "./IFeeDistributor.sol";
import "./IGauge.sol";
import "./IRewardsDistributor.sol";
import "./Initializable.sol";

contract RamsesLens is Initializable {
    IVoter voter;
    IVotingEscrow ve;
    IMinter minter;

    address public router; // router address

    struct Pool {
        address id;
        string symbol;
        bool stable;
        address token0;
        address token1;
        address gauge;
        address feeDistributor;
        address pairFees;
        uint pairBps;
    }

    struct ProtocolMetadata {
        address veAddress;
        address ramAddress;
        address voterAddress;
        address poolsFactoryAddress;
        address gaugesFactoryAddress;
        address minterAddress;
    }

    struct vePosition {
        uint256 tokenId;
        uint256 balanceOf;
        uint256 locked;
    }

    struct tokenRewardData {
        address token;
        uint rewardRate;
    }

    struct gaugeRewardsData {
        address gauge;
        tokenRewardData[] rewardData;
    }

    // user earned per token
    struct userGaugeTokenData {
        address token;
        uint earned;
    }

    struct userGaugeRewardData {
        address gauge;
        uint balance;
        uint derivedBalance;
        userGaugeTokenData[] userRewards;
    }

    // user earned per token for feeDist
    struct userBribeTokenData {
        address token;
        uint earned;
    }

    struct userFeeDistData {
        address feeDistributor;
        userBribeTokenData[] bribeData;
    }
    // the amount of nested structs for bribe lmao
    struct userBribeData {
        uint tokenId;
        userFeeDistData[] feeDistRewards;
    }

    struct userVeData {
        uint tokenId;
        uint lockedAmount;
        uint votingPower;
        uint lockEnd;
    }

    struct Earned {
        address poolAddress;
        address token;
        uint256 amount;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(IVoter _voter, address _router) external initializer {
        voter = _voter;
        router = _router;
        ve = IVotingEscrow(voter._ve());
        minter = IMinter(voter.minter());
    }

    /**
     * @notice returns the pool factory address
     */
    function poolFactory() public view returns (address pool) {
        pool = voter.factory();
    }

    /**
     * @notice returns the gauge factory address
     */
    function gaugeFactory() public view returns (address _gaugeFactory) {
        _gaugeFactory = voter.gaugefactory();
    }

    /**
     * @notice returns the fee distributor factory address
     */
    function feeDistributorFactory()
        public
        view
        returns (address _gaugeFactory)
    {
        _gaugeFactory = voter.feeDistributorFactory();
    }

    /**
     * @notice returns ram address
     */
    function ramAddress() public view returns (address ram) {
        ram = ve.token();
    }

    /**
     * @notice returns the voter address
     */
    function voterAddress() public view returns (address _voter) {
        _voter = address(voter);
    }

    /**
     * @notice returns rewardsDistributor address
     */
    function rewardsDistributor()
        public
        view
        returns (address _rewardsDistributor)
    {
        _rewardsDistributor = address(minter._rewards_distributor());
    }

    /**
     * @notice returns the minter address
     */
    function minterAddress() public view returns (address _minter) {
        _minter = address(minter);
    }

    /**
     * @notice returns Ramses core contract addresses
     */
    function protocolMetadata()
        external
        view
        returns (ProtocolMetadata memory)
    {
        return
            ProtocolMetadata({
                veAddress: voter._ve(),
                voterAddress: voterAddress(),
                ramAddress: ramAddress(),
                poolsFactoryAddress: poolFactory(),
                gaugesFactoryAddress: gaugeFactory(),
                minterAddress: minterAddress()
            });
    }

    /**
     * @notice returns all Ramses pool addresses
     */
    function allPools() public view returns (address[] memory pools) {
        IPairFactory _factory = IPairFactory(poolFactory());
        uint len = _factory.allPairsLength();

        pools = new address[](len);
        for (uint i; i < len; ++i) {
            pools[i] = _factory.allPairs(i);
        }
    }

    /**
     * @notice returns all Ramses pools that have active gauges
     */
    function allActivePools() public view returns (address[] memory pools) {
        uint len = voter.length();
        pools = new address[](len);

        for (uint i; i < len; ++i) {
            pools[i] = voter.pools(i);
        }
    }

    /**
     * @notice returns the gauge address for a pool
     * @param pool pool address to check
     */
    function gaugeForPool(address pool) public view returns (address gauge) {
        gauge = voter.gauges(pool);
    }

    /**
     * @notice returns the feeDistributor address for a pool
     * @param pool pool address to check
     */
    function feeDistributorForPool(
        address pool
    ) public view returns (address feeDistributor) {
        address gauge = gaugeForPool(pool);
        feeDistributor = voter.feeDistributers(gauge);
    }

    /**
     * @notice returns current fee rate of a ramses pool
     * @param pool pool address to check
     */
    function pairBps(address pool) public view returns (uint bps) {
        bps = IPairFactory(poolFactory()).pairFee(pool);
    }

    /**
     * @notice returns useful information for a pool
     * @param pool pool address to check
     */
    function poolInfo(
        address pool
    ) public view returns (Pool memory _poolInfo) {
        IPair pair = IPair(pool);
        _poolInfo.id = pool;
        _poolInfo.symbol = pair.symbol();
        (_poolInfo.token0, _poolInfo.token1) = pair.tokens();
        _poolInfo.gauge = gaugeForPool(pool);
        _poolInfo.feeDistributor = feeDistributorForPool(pool);
        _poolInfo.pairFees = pair.fees();
        _poolInfo.pairBps = pairBps(pool);
    }

    /**
     * @notice returns useful information for all Ramses pools
     */
    function allPoolsInfo() public view returns (Pool[] memory _poolsInfo) {
        address[] memory pools = allPools();
        uint len = pools.length;

        _poolsInfo = new Pool[](len);
        for (uint i; i < len; ++i) {
            _poolsInfo[i] = poolInfo(pools[i]);
        }
    }

    /**
     * @notice returns the gauge address for all active pairs
     */
    function allGauges() public view returns (address[] memory gauges) {
        address[] memory pools = allActivePools();
        uint len = pools.length;
        gauges = new address[](len);

        for (uint i; i < len; ++i) {
            gauges[i] = gaugeForPool(pools[i]);
        }
    }

    /**
     * @notice returns the feeDistributor address for all active pairs
     */
    function allFeeDistributors()
        public
        view
        returns (address[] memory feeDistributors)
    {
        address[] memory pools = allActivePools();
        uint len = pools.length;
        feeDistributors = new address[](len);

        for (uint i; i < len; ++i) {
            feeDistributors[i] = feeDistributorForPool(pools[i]);
        }
    }

    /**
     * @notice returns all reward tokens for the fee distributor of a pool
     * @param pool pool address to check
     */
    function bribeRewardsForPool(
        address pool
    ) public view returns (address[] memory rewards) {
        IFeeDistributor feeDist = IFeeDistributor(feeDistributorForPool(pool));
        rewards = feeDist.getRewardTokens();
    }

    /**
     * @notice returns all reward tokens for the gauge of a pool
     * @param pool pool address to check
     */
    function gaugeRewardsForPool(
        address pool
    ) public view returns (address[] memory rewards) {
        IGauge gauge = IGauge(gaugeForPool(pool));
        if (address(gauge) == address(0)) return rewards;

        uint len = gauge.rewardsListLength();
        rewards = new address[](len);
        for (uint i; i < len; ++i) {
            rewards[i] = gauge.rewards(i);
        }
    }

    /**
     * @notice returns all token id's of a user
     * @param user account address to check
     */
    function veNFTsOf(address user) public view returns (uint[] memory NFTs) {
        uint len = ve.balanceOf(user);
        NFTs = new uint[](len);

        for (uint i; i < len; ++i) {
            NFTs[i] = ve.tokenOfOwnerByIndex(user, i);
        }
    }

    /**
     * @notice returns bribes data of a token id per pool
     * @param tokenId the veNFT token id to check
     * @param pool the pool address
     */
    function bribesPositionOf(
        uint tokenId,
        address pool
    ) public view returns (userFeeDistData memory rewardsData) {
        IFeeDistributor feeDist = IFeeDistributor(feeDistributorForPool(pool));
        if (address(feeDist) == address(0)) {
            return rewardsData;
        }

        address[] memory rewards = bribeRewardsForPool(pool);
        uint len = rewards.length;

        rewardsData.feeDistributor = address(feeDist);
        userBribeTokenData[] memory _userRewards = new userBribeTokenData[](
            len
        );

        for (uint i; i < len; ++i) {
            _userRewards[i].token = rewards[i];
            _userRewards[i].earned = feeDist.earned(rewards[i], tokenId);
        }
        rewardsData.bribeData = _userRewards;
    }

    /**
     * @notice returns gauge reward data for a Ramses pool
     * @param pool Ramses pool address
     */
    function poolRewardsData(
        address pool
    ) public view returns (gaugeRewardsData memory rewardData) {
        address gauge = gaugeForPool(pool);
        if (gauge == address(0)) {
            return rewardData;
        }

        address[] memory rewards = gaugeRewardsForPool(pool);
        uint len = rewards.length;
        tokenRewardData[] memory _rewardData = new tokenRewardData[](len);

        for (uint i; i < len; ++i) {
            _rewardData[i].token = rewards[i];
            _rewardData[i].rewardRate = IGauge(gauge).rewardRate(rewards[i]);
        }
        rewardData.gauge = gauge;
        rewardData.rewardData = _rewardData;
    }

    /**
     * @notice returns gauge reward data for multiple ramses pools
     * @param pools Ramses pools addresses
     */
    function poolsRewardsData(
        address[] memory pools
    ) public view returns (gaugeRewardsData[] memory rewardsData) {
        uint len = pools.length;
        rewardsData = new gaugeRewardsData[](len);

        for (uint i; i < len; ++i) {
            rewardsData[i] = poolRewardsData(pools[i]);
        }
    }

    /**
     * @notice returns gauge reward data for all ramses pools
     */
    function allPoolsRewardData()
        public
        view
        returns (gaugeRewardsData[] memory rewardsData)
    {
        address[] memory pools = allActivePools();
        rewardsData = poolsRewardsData(pools);
    }

    /**
     * @notice returns veNFT lock data for a token id
     * @param user account address of the user
     */
    function vePositionsOf(
        address user
    ) public view returns (userVeData[] memory veData) {
        uint[] memory ids = veNFTsOf(user);
        uint len = ids.length;
        veData = new userVeData[](len);

        for (uint i; i < len; ++i) {
            veData[i].tokenId = ids[i];
            IVotingEscrow.LockedBalance memory _locked = ve.locked(ids[i]);
            veData[i].lockedAmount = uint(int(_locked.amount));
            veData[i].lockEnd = _locked.end;
            veData[i].votingPower = ve.balanceOfNFT(ids[i]);
        }
    }

    function tokenIdEarned(
        uint256 tokenId,
        address[] memory poolAddresses,
        address[][] memory rewardTokens,
        uint256 maxReturn
    ) external view returns (Earned[] memory earnings) {
        earnings = new Earned[](maxReturn);
        uint256 earningsIndex = 0;
        uint256 amount;

        for (uint256 i; i < poolAddresses.length; ++i) {
            IGauge gauge = IGauge(voter.gauges(poolAddresses[i]));

            if (address(gauge) != address(0)) {
                IFeeDistributor feeDistributor = IFeeDistributor(
                    voter.feeDistributers(address(gauge))
                );

                for (uint256 j; j < rewardTokens[i].length; ++j) {
                    amount = feeDistributor.earned(rewardTokens[i][j], tokenId);
                    if (amount > 0) {
                        earnings[earningsIndex++] = Earned({
                            poolAddress: poolAddresses[i],
                            token: rewardTokens[i][j],
                            amount: amount
                        });
                        require(
                            earningsIndex < maxReturn,
                            "Increase maxReturn"
                        );
                    }
                }
            }
        }
    }

    function addressEarned(
        address user,
        address[] memory poolAddresses,
        uint256 maxReturn
    ) external view returns (Earned[] memory earnings) {
        earnings = new Earned[](maxReturn);
        uint256 earningsIndex = 0;
        uint256 amount;

        for (uint256 i; i < poolAddresses.length; ++i) {
            IGauge gauge = IGauge(voter.gauges(poolAddresses[i]));

            if (address(gauge) != address(0)) {
                uint256 tokensCount = gauge.rewardsListLength();
                for (uint256 j; j < tokensCount; ++j) {
                    address token = gauge.rewards(j);
                    amount = gauge.earned(token, user);
                    if (amount > 0) {
                        earnings[earningsIndex++] = Earned({
                            poolAddress: poolAddresses[i],
                            token: token,
                            amount: amount
                        });
                        require(
                            earningsIndex < maxReturn,
                            "Increase maxReturn"
                        );
                    }
                }
            }
        }
    }

    function tokenIdRebase(
        uint256 tokenId
    ) external view returns (uint256 rebase) {
        rebase = IRewardsDistributor(rewardsDistributor()).claimable(tokenId);
    }
}

