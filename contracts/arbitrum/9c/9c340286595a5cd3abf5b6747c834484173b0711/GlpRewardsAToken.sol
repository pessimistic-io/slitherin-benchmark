// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import {IERC20} from "./contracts_IERC20.sol";
import {SafeMath} from "./SafeMath.sol";
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
    using SafeMath for uint256;

    /* ========== CONTSTANTS ========== */
    uint256 constant RATIO_DIVISOR = 10000;

    /* Gmx Reward Router Address */
    IRewardsRouterV2 public gmxRewardRouter;

    /* Distributor of claimed rewards */
    address public rewardDistributor;

    /* Weth address */
    IERC20 public weth;

    /* Parameters to pass to gmxRewardRouter*/
    bool shouldClaimGmx;
    bool shouldStakeGmx;
    bool shouldClaimEsGmx;
    bool shouldStakeEsGmx;
    bool shouldStakeMultiplierPoints;
    bool shouldClaimWeth;
    bool shouldConvertWethToEth;

    /* Pool profit ratio */
    uint256 profitRatio; // 100% = 10000;
    address treasuryAddress;

    constructor(IPool _pool) AToken(_pool) {}

    function setParameters(
        address _rewardDistributor,
        address _gmxRewardRouter,
        address _weth,
        bool[] calldata _rewardRouterParams,
        address _treasuryAddress,
        uint256 _profitRatio
    ) external onlyPoolAdmin {
        require(
            _rewardRouterParams.length == 7,
            "Rewards route must have 7 params"
        );
        require(_profitRatio <= RATIO_DIVISOR, "Invalid profit ratio");
        rewardDistributor = _rewardDistributor;
        gmxRewardRouter = IRewardsRouterV2(_gmxRewardRouter);
        weth = IERC20(_weth);

        shouldClaimGmx = _rewardRouterParams[0];
        shouldStakeGmx = _rewardRouterParams[1];
        shouldClaimEsGmx = _rewardRouterParams[2];
        shouldStakeEsGmx = _rewardRouterParams[3];
        shouldStakeMultiplierPoints = _rewardRouterParams[4];
        shouldClaimWeth = _rewardRouterParams[5];
        shouldConvertWethToEth = _rewardRouterParams[6];
        treasuryAddress = _treasuryAddress;
        profitRatio = _profitRatio;
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
                shouldClaimGmx,
                shouldStakeGmx,
                shouldClaimEsGmx,
                shouldStakeEsGmx,
                shouldStakeMultiplierPoints,
                shouldClaimWeth,
                shouldConvertWethToEth
            );
        }

        if (treasuryAddress != address(0)) {
            if (profitRatio != 0) {
                uint256 wethToTreasury = weth
                    .balanceOf(address(this))
                    .mul(profitRatio)
                    .div(RATIO_DIVISOR);
                weth.transfer(treasuryAddress, wethToTreasury);
            }
        }

        if (address(rewardDistributor) != address(0)) {
            uint256 wethBalance = weth.balanceOf(address(this));
            weth.transfer(rewardDistributor, wethBalance);
        }
    }
}

