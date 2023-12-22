// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./IVault.sol";
import "./IRewardRouterV2.sol";
import "./IGlpManager.sol";
import "./BaseBuildingBlock.sol";

/**
 * @author DeCommas team
 * @title GMX DEX interface
 */
contract GmxVault is BaseBuildingBlock {
    IVault public gmxVault;
    IRewardRouterV2 public rewardRouter;
    IGlpManager public glpManager;
    IERC20 public glpToken;
    IERC20 public glpTrackerToken;

    event BuyingEvent(IERC20 token, uint256 amount, uint256 glpAmountReceived);
    event SellingEvent(address receiver, uint256 glpAmount, IERC20 tokenOut);

    function initialize(bytes memory _data) public initializer {
        (
            IVault gmxVaultAddress,
            IRewardRouterV2 rewardRouterAddress,
            IActionPoolDcRouter actionPoolDcRouter,
            uint16 actionPoolId,
            ILayerZeroEndpointUpgradeable nativeLZEndpoint,
            uint16 nativeId,
            IERC20 usdcToken
        ) = abi.decode(
                _data,
                (
                    IVault,
                    IRewardRouterV2,
                    IActionPoolDcRouter,
                    uint16,
                    ILayerZeroEndpointUpgradeable,
                    uint16,
                    IERC20
                )
            );

        require(address(gmxVaultAddress) != address(0), "GMX BB: zero address");
        require(
            address(rewardRouterAddress) != address(0),
            "GMX BB: zero address"
        );
        require(
            address(actionPoolDcRouter) != address(0),
            "GMX BB: zero address"
        );
        require(
            address(nativeLZEndpoint) != address(0),
            "GMX BB: zero address"
        );
        require(address(usdcToken) != address(0), "GMX BB: zero address");
        require(nativeId > 0, "GMX BB: zero id.");

        __Ownable_init();
        __LzAppUpgradeable_init(address(nativeLZEndpoint));
        _transferOwnership(_msgSender());

        _nativeChainId = nativeId;
        _currentUSDCToken = address(usdcToken);
        lzEndpoint = nativeLZEndpoint;
        trustedRemoteLookup[actionPoolId] = abi.encodePacked(
            address(actionPoolDcRouter),
            address(this)
        );
        _actionPool = address(actionPoolDcRouter);

        gmxVault = gmxVaultAddress;
        rewardRouter = rewardRouterAddress;
        glpManager = IGlpManager(rewardRouter.glpManager());
        glpToken = IERC20(rewardRouter.glp());
        glpTrackerToken = IERC20(rewardRouter.stakedGlpTracker());
    }

    /**
     * @notice buy GLP, mint and stake
     * @param _data :
     * @dev token : the token to buy GLP with
     * @dev amount : the amount of token to use for the purchase
     * @dev minUsdg : the minimum acceptable USD value of the GLP purchased // do we calculate on chain or off?
     * @dev minGlp : the minimum acceptable GLP amount
     * @dev Rewards router and GLP manager spent must be approved before
     * @dev glpTrackerToken is 1:1 ratio with glp token
     * @dev access restricted to only self base buildingblock call
     **/
    function buyGLP(bytes memory _data)
        external
        returns (uint256 glpBoughtAmount)
    {
        (IERC20 token, uint256 amount, uint256 minUsdg, uint256 minGlp) = abi
            .decode(_data, (IERC20, uint256, uint256, uint256));
        require(address(token) != address(0), "GMX BB: Invalid asset");
        require(amount > 0, "GMX BB: Zero amoun");
        if (address(token) == address(0x0)) {
            require(
                address(this).balance >= amount,
                "GMX BB: Bridge or deposit native currency"
            );
            glpBoughtAmount = rewardRouter.mintAndStakeGlpETH{value: amount}(
                minUsdg,
                minGlp
            );
        } else {
            require(amount > 0, "GMX BB: Zero amount");

            // check for balance to buy with
            require(
                token.balanceOf(address(this)) >= amount,
                "GMX BB: Bridge or deposit assets."
            );

            // approve to void contracts is necessary
            token.approve(address(rewardRouter), amount);
            token.approve(address(glpManager), amount);

            // get GLP balance after buying
            uint256 glpBalanceBefore = glpTrackerToken.balanceOf(address(this));
            // // buy Glp
            glpBoughtAmount = rewardRouter.mintAndStakeGlp(
                address(token), // the token to buy GLP with
                amount, // the amount of token to use for the purchase
                minUsdg, // the minimum acceptable USD value of the GLP purchased
                minGlp // minimum acceptable GLP amount
            );
            // check glp balance after buying
            uint256 glpBalanceAfter = glpTrackerToken.balanceOf(address(this));

            require(
                glpBalanceBefore + glpBoughtAmount >= glpBalanceAfter,
                "GMX BB: Glp buying failed."
            );
        }
        emit BuyingEvent(token, amount, glpBoughtAmount);
    }

    /**
     *   @notice Sell / unstake and redeem GLP
     *   @param _data encoded params:
     *   @dev tokenOut : the token to sell GLP for
     *   @dev glpAmount : the amount of GLP to sell
     *   @dev minOut : the minimum acceptable amount of tokenOut to be received
     *   @return amountPayed payed for the sell
     *   @dev access restricted to only self base buildingblock call
     * */
    function sellGLP(bytes memory _data)
        external
        returns (uint256 amountPayed)
    {
        (IERC20 tokenOut, uint256 glpAmount, uint256 minOut) = abi.decode(
            _data,
            (IERC20, uint256, uint256)
        );
        if (address(tokenOut) == address(0x0)) {
            amountPayed = rewardRouter.unstakeAndRedeemGlpETH(
                glpAmount,
                minOut,
                payable(address(this))
            );
        } else {
            // unstake And Redeem Glp
            uint256 tokenOutBalanceBefore = tokenOut.balanceOf(address(this));
            amountPayed = rewardRouter.unstakeAndRedeemGlp(
                address(tokenOut),
                glpAmount,
                minOut,
                address(this)
            );
            // get contract balance after selling
            uint256 tokenOutBalanceAfter = tokenOut.balanceOf(address(this));

            // get balance change
            uint256 balanceChange = tokenOutBalanceAfter -
                tokenOutBalanceBefore;

            // check if vault balance reflects the sale
            require(
                balanceChange >= amountPayed,
                "GMX BB: Glp buying failed. "
            );
        }

        emit SellingEvent(msg.sender, glpAmount, tokenOut);
        return amountPayed;
    }

    /**
     *  @notice Trigger rewards compounding and claims them
     *  @param _data :
     *  @dev _shouldClaimGmx boolean yes/no
     *  @dev _shouldStakeGmx boolean yes/no
     *  @dev _shouldClaimEsGmx boolean yes/no
     *  @dev _shouldStakeEsGmx boolean yes/no
     *  @dev _shouldStakeMultiplierPoints boolean yes/no
     *  @dev _shouldClaimWeth boolean yes/no
     *  @dev _shouldConvertWethToEth boolean yes/no
     *  @dev 15 avrg min cooldown time
     *   @dev access restricted to only self base buildingblock call
     */
    function claimRewards(bytes memory _data) external returns (bool) {
        (
            bool shouldClaimGmx,
            bool shouldStakeGmx,
            bool shouldClaimEsGmx,
            bool shouldStakeEsGmx,
            bool shouldStakeMultiplierPoints,
            bool shouldClaimWeth,
            bool shouldConvertWethToEth
        ) = abi.decode(_data, (bool, bool, bool, bool, bool, bool, bool));
        rewardRouter.handleRewards(
            shouldClaimGmx,
            shouldStakeGmx,
            shouldClaimEsGmx,
            shouldStakeEsGmx,
            shouldStakeMultiplierPoints,
            shouldClaimWeth,
            shouldConvertWethToEth
        );
        return true;
    }

    function getTvl() public view override returns (uint256) {
        uint256 glpPrice = glpManager.getAum(true) / glpToken.totalSupply();
        uint256 fsGlpAmount = glpTrackerToken.balanceOf(address(this));
        return fsGlpAmount * glpPrice;
    }

    /**
     * @notice Calculate asset pool weight of glp index on USD
     * @param _assets list of glp index tokens
     * @return list of token pool weights in usd
     */
    function getWeights(IERC20[] calldata _assets)
        external
        view
        returns (uint256[] memory)
    {
        uint256[] memory aums = new uint256[](_assets.length);
        uint256 sum = glpManager.getAum(true);

        for (uint256 i; i < _assets.length; i++) {
            uint256 price = gmxVault.getMaxPrice(address(_assets[i]));
            uint256 poolAmount = gmxVault.poolAmounts(address(_assets[i]));
            uint256 decimals = gmxVault.tokenDecimals(address(_assets[i]));

            if (gmxVault.stableTokens(address(_assets[i]))) {
                aums[i] = (poolAmount * price) / (10**decimals);
            } else {
                aums[i] = gmxVault.guaranteedUsd(address(_assets[i]));
                uint256 reservedAmount = gmxVault.reservedAmounts(
                    address(_assets[i])
                );
                aums[i] +=
                    ((poolAmount - reservedAmount) * price) /
                    (10**decimals);

                uint256 size = gmxVault.globalShortSizes(address(_assets[i]));
                if (size > 0) {
                    (bool hasProfit, uint256 delta) = gmxVault
                        .getGlobalShortDelta(address(_assets[i]));
                    if (!hasProfit) {
                        aums[i] += delta;
                    } else {
                        aums[i] -= delta;
                    }
                }
            }
            aums[i] = (aums[i] * 1e18) / sum;
        }
        return aums;
    }

    uint256[50] private __gap;
}

