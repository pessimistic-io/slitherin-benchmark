// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./SafeMath.sol";
import "./SignedSafeMath.sol";
import "./SafeERC20.sol";
import "./OwnableUpgradeable.sol";

import "./TransferHelper.sol";
import "./IBribeManager.sol";
import "./IDelegateVotePool.sol";
import "./INativeZapper.sol";
import "./IVirtualBalanceRewardPool.sol";
import "./IVlQuoV2.sol";
import "./IWombatVoterProxy.sol";
import "./IVoter.sol";
import "./IVeWom.sol";

contract BribeManager is IBribeManager, OwnableUpgradeable {
    using SafeMath for uint256;
    using SignedSafeMath for int256;
    using SafeERC20 for IERC20;

    IVoter public voter;
    IVeWom public veWom;

    IWombatVoterProxy public voterProxy;
    IVlQuoV2 public vlQuoV2;
    INativeZapper public nativeZapper;

    address public delegatePool;

    struct Pool {
        address lpToken;
        address rewarder;
        bool isActive;
    }

    address[] public pools;
    mapping(address => Pool) public poolInfos;

    mapping(address => uint256) public poolTotalVote;
    mapping(address => uint256) public userTotalVote;
    mapping(address => mapping(address => uint256)) public userVoteForPools; // unit = vlQuo

    uint256 public totalVlQuoInVote;
    uint256 public lastCastTimer;
    uint256 public castVotesCooldown;

    function initialize() public initializer {
        __Ownable_init();
    }

    function setParams(
        address _voter,
        address _voterProxy,
        address _vlQuoV2,
        address _nativeZapper,
        address _delegatePool
    ) external onlyOwner {
        require(address(voter) == address(0), "params have already been set");

        require(_voter != address(0), "invalid _voter!");
        require(_voterProxy != address(0), "invalid _voterProxy!");
        require(_vlQuoV2 != address(0), "invalid _vlQuoV2!");
        require(_nativeZapper != address(0), "invalid _nativeZapper!");
        require(_delegatePool != address(0), "invalid _delegatePool!");

        voter = IVoter(_voter);
        veWom = IVeWom(voter.veWom());

        voterProxy = IWombatVoterProxy(_voterProxy);
        vlQuoV2 = IVlQuoV2(_vlQuoV2);
        nativeZapper = INativeZapper(_nativeZapper);

        delegatePool = _delegatePool;

        castVotesCooldown = 60;
    }

    function setDelegatePool(address _delegatePool) external onlyOwner {
        require(_delegatePool != address(0), "invalid _delegatePool!");

        delegatePool = _delegatePool;
    }

    function getUserTotalVote(address _user)
        external
        view
        override
        returns (uint256)
    {
        return userTotalVote[_user];
    }

    function getUserVoteForPool(address _lp, address _user)
        public
        view
        override
        returns (uint256)
    {
        return userVoteForPools[_user][_lp];
    }

    function getUserVoteForPools(address[] calldata _lps, address _user)
        external
        view
        override
        returns (uint256[] memory votes)
    {
        uint256 length = _lps.length;
        votes = new uint256[](length);
        for (uint256 i; i < length; i++) {
            votes[i] = getUserVoteForPool(_lps[i], _user);
        }
    }

    function getTotalVoteForPools(address[] calldata _lps)
        external
        view
        returns (uint256[] memory vlQuoVotes)
    {
        uint256 length = _lps.length;
        vlQuoVotes = new uint256[](length);
        for (uint256 i; i < length; i++) {
            vlQuoVotes[i] = poolTotalVote[_lps[i]];
        }
    }

    function getPoolsLength() external view returns (uint256) {
        return pools.length;
    }

    function getVeWomVoteForLp(address _lp) public view returns (uint256) {
        return voter.getUserVotes(address(voterProxy), _lp);
    }

    function getVeWomVoteForLps(address[] calldata _lps)
        external
        view
        returns (uint256[] memory votes)
    {
        uint256 length = _lps.length;
        votes = new uint256[](length);
        for (uint256 i; i < length; i++) {
            votes[i] = getVeWomVoteForLp(_lps[i]);
        }
    }

    function usedVote() public view returns (uint256) {
        return veWom.usedVote(address(voterProxy));
    }

    function totalVotes() public view returns (uint256) {
        return veWom.balanceOf(address(voterProxy));
    }

    function remainingVotes() external view returns (uint256) {
        return totalVotes().sub(usedVote());
    }

    function addPool(address _lp, address _rewarder) external onlyOwner {
        require(_lp != address(0), "_lp ZERO ADDRESS");
        if (_lp != delegatePool) {
            (, , , , , address gaugeManager, ) = voter.infos(_lp);
            require(gaugeManager != address(0), "gaugeManager ZERO ADDRESS");
        }

        Pool memory pool = Pool({
            lpToken: _lp,
            rewarder: _rewarder,
            isActive: true
        });
        if (_lp != delegatePool) {
            pools.push(_lp); // we don't want the delegatePool in this array
        }
        poolInfos[_lp] = pool;
        emit PoolAdded(_lp, _rewarder);
    }

    /// @notice Changes the votes to zero for all pools. Only internal.
    function _resetVotes() internal {
        uint256 length = pools.length;
        address[] memory lpVote = new address[](length);
        int256[] memory votes = new int256[](length);
        address[] memory rewarders = new address[](length);
        for (uint256 i; i < length; i++) {
            Pool memory pool = poolInfos[pools[i]];
            lpVote[i] = pool.lpToken;
            votes[i] = -int256(getVeWomVoteForLp(pool.lpToken));
            rewarders[i] = pool.rewarder;
        }
        voterProxy.vote(lpVote, votes, rewarders, address(0));
        emit AllVoteReset();
    }

    function isPoolActive(address pool) external view override returns (bool) {
        return poolInfos[pool].isActive;
    }

    function deactivatePool(address _lp) external onlyOwner {
        poolInfos[_lp].isActive = false;
    }

    /// @notice Changes the votes to zero for all pools. Only internal.
    /// @dev This would entirely kill all votings
    function clearPools() external onlyOwner {
        _resetVotes();
        uint256 length = pools.length;
        for (uint256 i; i < length; i++) {
            poolInfos[pools[i]].isActive = false;
        }
        delete pools;
    }

    function removePool(uint256 _index) external onlyOwner {
        uint256 length = pools.length;
        pools[_index] = pools[length - 1];
        pools.pop();
    }

    function getUserLocked(address _user) public view returns (uint256) {
        return
            _user == delegatePool
                ? poolTotalVote[delegatePool]
                : vlQuoV2.balanceOf(_user);
    }

    /// @notice Vote on pools. Need to compute the delta prior to casting this.
    function vote(address[] calldata _lps, int256[] calldata _deltas)
        external
        override
    {
        uint256 length = _lps.length;
        int256 totalUserVote;
        for (uint256 i; i < length; i++) {
            Pool memory pool = poolInfos[_lps[i]];
            require(pool.isActive, "Not active");
            int256 delta = _deltas[i];
            totalUserVote = totalUserVote.add(delta);
            if (delta != 0) {
                if (delta > 0) {
                    poolTotalVote[pool.lpToken] = poolTotalVote[pool.lpToken]
                        .add(uint256(delta));
                    userTotalVote[msg.sender] = userTotalVote[msg.sender].add(
                        uint256(delta)
                    );
                    userVoteForPools[msg.sender][
                        pool.lpToken
                    ] = userVoteForPools[msg.sender][pool.lpToken].add(
                        uint256(delta)
                    );
                    IVirtualBalanceRewardPool(pool.rewarder).stakeFor(
                        msg.sender,
                        uint256(delta)
                    );
                } else {
                    poolTotalVote[pool.lpToken] = poolTotalVote[pool.lpToken]
                        .sub(uint256(-delta));
                    userTotalVote[msg.sender] = userTotalVote[msg.sender].sub(
                        uint256(-delta)
                    );
                    userVoteForPools[msg.sender][
                        pool.lpToken
                    ] = userVoteForPools[msg.sender][pool.lpToken].sub(
                        uint256(-delta)
                    );
                    IVirtualBalanceRewardPool(pool.rewarder).withdrawFor(
                        msg.sender,
                        uint256(-delta)
                    );
                }

                emit VoteUpdated(
                    msg.sender,
                    pool.lpToken,
                    userVoteForPools[msg.sender][pool.lpToken]
                );
            }
        }
        if (msg.sender != delegatePool) {
            // this already gets updated when a user vote for the delegate pool
            if (totalUserVote > 0) {
                totalVlQuoInVote = totalVlQuoInVote.add(uint256(totalUserVote));
            } else {
                totalVlQuoInVote = totalVlQuoInVote.sub(
                    uint256(-totalUserVote)
                );
            }
        }
        require(
            userTotalVote[msg.sender] <= getUserLocked(msg.sender),
            "Above vote limit"
        );
    }

    /// @notice Unvote from an inactive pool. This makes it so that deleting a pool, or changing a rewarder doesn't block users from withdrawing
    function unvote(address _lp) external override {
        Pool memory pool = poolInfos[_lp];
        uint256 currentVote = userVoteForPools[msg.sender][pool.lpToken];
        if (currentVote == 0) {
            return;
        }
        require(!pool.isActive, "Active");
        poolTotalVote[pool.lpToken] = poolTotalVote[pool.lpToken].sub(
            currentVote
        );
        userTotalVote[msg.sender] = userTotalVote[msg.sender].sub(currentVote);
        userVoteForPools[msg.sender][pool.lpToken] = 0;
        IVirtualBalanceRewardPool(pool.rewarder).withdrawFor(
            msg.sender,
            currentVote
        );
        if (msg.sender != delegatePool) {
            totalVlQuoInVote = totalVlQuoInVote.sub(currentVote);
        }

        emit VoteUpdated(
            msg.sender,
            pool.lpToken,
            userVoteForPools[msg.sender][pool.lpToken]
        );
    }

    /// @notice cast all pending votes
    /// @notice this function will be gas intensive, hence a fee is given to the caller
    function castVotes(bool _swapForNative)
        public
        returns (
            address[][] memory finalRewardTokens,
            uint256[][] memory finalFeeAmounts
        )
    {
        require(
            block.timestamp - lastCastTimer > castVotesCooldown,
            "Last cast too recent"
        );
        lastCastTimer = block.timestamp;
        uint256 length = pools.length;
        address[] memory lpVote = new address[](length);
        int256[] memory votes = new int256[](length);
        address[] memory rewarders = new address[](length);
        for (uint256 i; i < length; i++) {
            Pool memory pool = poolInfos[pools[i]];
            lpVote[i] = pool.lpToken;
            rewarders[i] = pool.rewarder;

            uint256 currentVote = getVeWomVoteForLp(pool.lpToken);
            uint256 targetVote = poolTotalVote[pool.lpToken]
                .mul(totalVotes())
                .div(totalVlQuoInVote);
            if (targetVote >= currentVote) {
                votes[i] = int256(targetVote.sub(currentVote));
            } else {
                votes[i] = int256(targetVote).sub(int256(currentVote));
            }
        }
        (
            address[][] memory rewardTokens,
            uint256[][] memory feeAmounts
        ) = voterProxy.vote(lpVote, votes, rewarders, msg.sender);

        finalRewardTokens = new address[][](length);
        finalFeeAmounts = new uint256[][](length);
        if (_swapForNative) {
            for (uint256 i = 0; i < length; i++) {
                finalRewardTokens[i] = new address[](1);
                finalRewardTokens[i][0] = AddressLib.PLATFORM_TOKEN_ADDRESS;
                finalFeeAmounts[i] = new uint256[](1);
                finalFeeAmounts[i][0] = finalFeeAmounts[i][0].add(
                    _swapFeesForNative(
                        rewardTokens[i],
                        feeAmounts[i],
                        msg.sender
                    )
                );
            }
        } else {
            for (uint256 i = 0; i < length; i++) {
                _forwardRewards(rewardTokens[i], feeAmounts[i]);
                finalRewardTokens[i] = rewardTokens[i];
                finalFeeAmounts[i] = feeAmounts[i];
            }
        }
    }

    /// @notice Cast a zero vote to harvest the bribes of selected pools
    /// @notice this function has a lesser importance than casting votes, hence no rewards will be given to the caller.
    function harvestPools(address[] calldata _lps) external {
        uint256 length = _lps.length;
        int256[] memory votes = new int256[](length);
        address[] memory rewarders = new address[](length);
        for (uint256 i; i < length; i++) {
            address lp = _lps[i];
            Pool memory pool = poolInfos[lp];
            rewarders[i] = pool.rewarder;
            votes[i] = 0;
        }
        voterProxy.vote(_lps, votes, rewarders, address(0));
    }

    /// @notice Harvests user rewards for each pool
    /// @notice If bribes weren't harvested, this might be lower than actual current value
    function getRewardForPools(address[] calldata _lps) external {
        uint256 length = _lps.length;
        for (uint256 i; i < length; i++) {
            if (_lps[i] == delegatePool) {
                IDelegateVotePool(delegatePool).getReward(msg.sender);
            } else {
                IVirtualBalanceRewardPool(poolInfos[_lps[i]].rewarder)
                    .getReward(msg.sender);
            }
        }
    }

    /// @notice Harvests user rewards for each pool where he has voted
    /// @notice If bribes weren't harvested, this might be lower than actual current value
    function getRewardAll()
        external
        override
        returns (
            address[][] memory rewardTokens,
            uint256[][] memory earnedRewards
        )
    {
        address[] memory delegatePoolRewardTokens;
        uint256[] memory delegatePoolRewardAmounts;
        if (userVoteForPools[msg.sender][delegatePool] > 0) {
            (
                delegatePoolRewardTokens,
                delegatePoolRewardAmounts
            ) = IDelegateVotePool(delegatePool).getReward(msg.sender);
        }
        uint256 length = pools.length;
        rewardTokens = new address[][](length + 1);
        earnedRewards = new uint256[][](length + 1);
        for (uint256 i; i < length; i++) {
            Pool memory pool = poolInfos[pools[i]];
            if (userVoteForPools[msg.sender][pool.lpToken] > 0) {
                rewardTokens[i] = IVirtualBalanceRewardPool(pool.rewarder)
                    .getRewardTokens();
                earnedRewards[i] = new uint256[](rewardTokens[i].length);
                for (uint256 j = 0; j < rewardTokens[i].length; j++) {
                    earnedRewards[i][j] = IVirtualBalanceRewardPool(
                        pool.rewarder
                    ).earned(msg.sender, rewardTokens[i][j]);
                }

                IVirtualBalanceRewardPool(pool.rewarder).getReward(msg.sender);
            }
        }

        rewardTokens[length] = delegatePoolRewardTokens;
        earnedRewards[length] = delegatePoolRewardAmounts;
    }

    function previewNativeAmountForCast(address[] calldata _lps)
        external
        view
        returns (uint256)
    {
        (
            address[][] memory rewardTokens,
            uint256[][] memory amounts
        ) = voterProxy.pendingBribeCallerFee(_lps);
        uint256 feeAmount = 0;
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            for (uint256 j = 0; j < rewardTokens[i].length; j++) {
                if (amounts[i][j] == 0) {
                    continue;
                }
                if (rewardTokens[i][j] == AddressLib.PLATFORM_TOKEN_ADDRESS) {
                    feeAmount = feeAmount.add(amounts[i][j]);
                } else {
                    feeAmount = feeAmount.add(
                        nativeZapper.getAmountOut(
                            rewardTokens[i][j],
                            amounts[i][j]
                        )
                    );
                }
            }
        }
        return feeAmount;
    }

    function earned(address _lp, address _for)
        external
        view
        returns (address[] memory rewardTokens, uint256[] memory amounts)
    {
        Pool memory pool = poolInfos[_lp];
        rewardTokens = IVirtualBalanceRewardPool(pool.rewarder)
            .getRewardTokens();
        uint256 length = rewardTokens.length;
        amounts = new uint256[](length);
        for (uint256 index; index < length; ++index) {
            amounts[index] = IVirtualBalanceRewardPool(pool.rewarder).earned(
                _for,
                rewardTokens[index]
            );
        }
    }

    function _forwardRewards(
        address[] memory _rewardTokens,
        uint256[] memory _feeAmounts
    ) internal {
        uint256 length = _rewardTokens.length;
        for (uint256 i; i < length; i++) {
            if (_rewardTokens[i] != address(0) && _feeAmounts[i] > 0) {
                TransferHelper.safeTransferToken(
                    _rewardTokens[i],
                    msg.sender,
                    _feeAmounts[i]
                );
            }
        }
    }

    function _swapFeesForNative(
        address[] memory rewardTokens,
        uint256[] memory feeAmounts,
        address _receiver
    ) internal returns (uint256 nativeAmount) {
        uint256 length = rewardTokens.length;
        for (uint256 i; i < length; i++) {
            if (feeAmounts[i] == 0) {
                continue;
            }
            if (AddressLib.isPlatformToken(rewardTokens[i])) {
                nativeAmount = nativeAmount.add(feeAmounts[i]);
                TransferHelper.safeTransferETH(_receiver, feeAmounts[i]);
            } else {
                _approveTokenIfNeeded(
                    rewardTokens[i],
                    address(nativeZapper),
                    feeAmounts[i]
                );
                nativeAmount = nativeAmount.add(
                    nativeZapper.zapInToken(
                        rewardTokens[i],
                        feeAmounts[i],
                        _receiver
                    )
                );
            }
        }
    }

    function _approveTokenIfNeeded(
        address _token,
        address _to,
        uint256 _amount
    ) internal {
        if (IERC20(_token).allowance(address(this), _to) < _amount) {
            IERC20(_token).safeApprove(_to, 0);
            IERC20(_token).safeApprove(_to, type(uint256).max);
        }
    }

    receive() external payable {}
}

