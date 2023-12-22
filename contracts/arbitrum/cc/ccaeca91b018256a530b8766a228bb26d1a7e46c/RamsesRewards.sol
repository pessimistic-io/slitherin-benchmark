// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./Initializable.sol";
import "./Math.sol";

import "./IFeeDistributor.sol";
import "./IGauge.sol";
import "./IRewardsDistributor.sol";
import "./IVoter.sol";

contract RamsesRewards is Initializable {
    enum EarningType {
        Gauge,
        FeeDistributor
    }
    struct Earned {
        address poolAddress;
        address token;
        uint256 amount;
        EarningType earningType;
    }

    IVoter public voter;
    IRewardsDistributor public rewardsDistributor;

    function initialize(
        address _voter,
        address _rewardsDistributor
    ) public initializer {
        voter = IVoter(_voter);
        rewardsDistributor = IRewardsDistributor(_rewardsDistributor);
    }

    function earned(
        address user,
        uint256 tokenId,
        address[] memory poolAddresses,
        uint256 maxReturn
    ) external view returns (uint256 rebase, Earned[] memory earnings) {
        earnings = new Earned[](maxReturn);
        uint256 earningsIndex = 0;
        uint256 amount;

        for (uint256 i; i < poolAddresses.length; ++i) {
            IGauge gauge = IGauge(voter.gauges(poolAddresses[i]));

            if (address(gauge) != address(0)) {
                if (tokenId != 0) {
                    IFeeDistributor feeDistributor = IFeeDistributor(
                        voter.feeDistributers(address(gauge))
                    );

                    rebase = rewardsDistributor.claimable(tokenId);

                    address[] memory tokens = feeDistributor.getRewardTokens();
                    for (uint256 j; j < tokens.length; ++j) {
                        amount = feeDistributor.earned(tokens[j], tokenId);
                        if (amount > 0) {
                            earnings[earningsIndex++] = Earned({
                                poolAddress: poolAddresses[i],
                                token: tokens[j],
                                amount: amount,
                                earningType: EarningType.FeeDistributor
                            });
                            require(
                                earningsIndex < maxReturn,
                                "Increase maxReturn"
                            );
                        }
                    }
                }
            }

            if (user != address(0)) {
                uint256 tokensCount = gauge.rewardsListLength();
                for (uint256 j; j < tokensCount; ++j) {
                    address token = gauge.rewards(j);
                    amount = gauge.earned(token, user);
                    if (amount > 0) {
                        earnings[earningsIndex++] = Earned({
                            poolAddress: poolAddresses[i],
                            token: token,
                            amount: amount,
                            earningType: EarningType.Gauge
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
}

