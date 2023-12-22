// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./Initializable.sol";
import "./Math.sol";

import "./IFeeDistributor.sol";
import "./IGauge.sol";
import "./IRewardsDistributor.sol";
import "./IVoter.sol";

import "./INonfungiblePositionManager.sol";
import "./IGaugeV2.sol";
import "./PoolAddress.sol";

contract RamsesRewards {
    struct Earned {
        address poolAddress;
        address token;
        uint256 amount;
    }

    IVoter public immutable voter;
    IRewardsDistributor public immutable rewardsDistributor;
    INonfungiblePositionManager public immutable nfpManager;
    address public immutable clPoolFactory;

    constructor(
        address _voter,
        address _rewardsDistributor,
        address _nfpManager,
        address _clPoolFactory
    ) {
        voter = IVoter(_voter);
        rewardsDistributor = IRewardsDistributor(_rewardsDistributor);
        nfpManager = INonfungiblePositionManager(_nfpManager);
        clPoolFactory = _clPoolFactory;
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

    function addressEarnedCl(
        address user,
        uint256 maxReturn
    ) external view returns (Earned[] memory earnings) {
        earnings = new Earned[](maxReturn);
        uint256 earningsIndex = 0;
        uint256 amount;

        // fetch user NFPs
        uint nfpAmount = nfpManager.balanceOf(user);

        for (uint i = 0; i < nfpAmount; ++i) {
            uint tokenId = nfpManager.tokenOfOwnerByIndex(user, i);

            (
                ,
                ,
                address token0,
                address token1,
                uint24 fee,
                ,
                ,
                ,
                ,
                ,
                ,

            ) = nfpManager.positions(tokenId);

            address poolAddress = PoolAddress.computeAddress(
                clPoolFactory,
                PoolAddress.PoolKey({token0: token0, token1: token1, fee: fee})
            );

            IGaugeV2 gauge = IGaugeV2(voter.gauges(poolAddress));
            if (address(gauge) != address(0)) {
                address[] memory rewards = gauge.getRewardTokens();

                for (uint j = 0; j < rewards.length; ++j) {
                    amount = gauge.earned(rewards[j], tokenId);

                    if (amount > 0) {
                        earnings[earningsIndex++] = Earned({
                            poolAddress: poolAddress,
                            token: rewards[j],
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
        rebase = rewardsDistributor.claimable(tokenId);
    }
}

