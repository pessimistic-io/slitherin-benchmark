// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./Initializable.sol";
import "./Math.sol";

import "./IFeeDistributor.sol";
import "./IGauge.sol";
import "./IRewardsDistributor.sol";
import "./IVoter.sol";

contract RamsesRewards {
    struct Earned {
        address poolAddress;
        address token;
        uint256 amount;
    }

    IVoter public voter;
    IRewardsDistributor public rewardsDistributor;

    constructor(address _voter, address _rewardsDistributor) {
        voter = IVoter(_voter);
        rewardsDistributor = IRewardsDistributor(_rewardsDistributor);
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
        rebase = rewardsDistributor.claimable(tokenId);
    }
}

