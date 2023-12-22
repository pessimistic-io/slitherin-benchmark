// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import {IERC20} from "./contracts_IERC20.sol";
import {GPv2SafeERC20} from "./GPv2SafeERC20.sol";
import {IPool} from "./IPool.sol";
import {AToken} from "./AToken.sol";

interface IRewardsRouterV2 {
    function handleRewards(
        bool _shouldClaimGmx,
        bool _shouldStakeGmx,
        bool _shouldClaimEsGmx,
        bool _shouldStakeEsGmx,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth
    ) external;
}

/**
 * @title   GlpRewardsAToken
 * @author  Maneki.finance
 * @notice  Customized AToken, used to auto claim ether rewards accumulated by Glp
 *          and forward it to distributor
 */

contract GlpRewardsAToken is AToken {
    using GPv2SafeERC20 for IERC20;

    IRewardsRouterV2 public gmxRewardRouter;
    address public rewardDistributor;
    IERC20 public weth;

    constructor(IPool _pool) AToken(_pool) {}

    function setParameters(
        address _rewardDistributor,
        address _gmxRewardsRouter,
        address _weth
    ) external onlyPoolAdmin {
        rewardDistributor = _rewardDistributor;
        gmxRewardRouter = IRewardsRouterV2(_gmxRewardsRouter);
        weth = IERC20(_weth);
    }

    function _transfer(
        address from,
        address to,
        uint128 amount
    ) internal virtual override {
        _claimRewards();
        super._transfer(from, to, amount, true);
    }

    function mint(
        address caller,
        address onBehalfOf,
        uint256 amount,
        uint256 index
    ) public virtual override onlyPool returns (bool) {
        _claimRewards();
        return super.mint(caller, onBehalfOf, amount, index);
    }

    function burn(
        address from,
        address receiverOfUnderlying,
        uint256 amount,
        uint256 index
    ) public virtual override onlyPool {
        _claimRewards();
        return super.burn(from, receiverOfUnderlying, amount, index);
    }

    function _claimRewards() internal {
        if (address(gmxRewardRouter) != address(0)) {
            gmxRewardRouter.handleRewards(
                false,
                false,
                false,
                false,
                false,
                true,
                false
            );
        }
        if (address(rewardDistributor) != address(0)) {
            uint256 wethBalance = weth.balanceOf(address(this));
            weth.transfer(rewardDistributor, wethBalance);
        }
    }
}

