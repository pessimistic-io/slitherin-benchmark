//SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.18;
import "./Interfaces.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./Whitelist.sol";
import "./Swap.sol";

//TODO: Add admin functions ? comment add to force deployment

contract RewardRouter is
    RouterConstants,
    Initializable,
    Swap,
    ReentrancyGuardUpgradeable
{
    uint256 public withdrawMantissa;
    Whitelist public WHITELIST;
    address public DISTRIBUTOR;
    uint256 public MAX_SLIPPAGE;

    event RewardsDistributed(uint256 rewards, uint256 timestamp);

    /**
     * @notice Initializer Function
     * @param lTokens[] The list of lToken markets to draw reserves from
     * @param underlyingTokens[] The list of underlying tokens for the markets IN THE SAME ORDER AS THE LTOKENS ARRAY
     * @param _whitelist The address of the governing whitelist contract
     * @param _distributor The address of the reward distributor (StakingRewards) contract
     */
    function initialize(
        address[] memory lTokens,
        address[] memory underlyingTokens,
        Whitelist _whitelist,
        address _distributor
    ) public initializer {
        withdrawMantissa = 5e17; //50%
        WHITELIST = _whitelist;
        DISTRIBUTOR = _distributor;
        MAX_SLIPPAGE = 1e16; //1%
        for (uint8 i = 0; i < underlyingTokens.length; i++) {
            if (lTokens[i] != lETH) {
                IERC20(underlyingTokens[i]).approve(
                    address(SUSHI_ROUTER),
                    type(uint256).max
                );
                IERC20(underlyingTokens[i]).approve(
                    address(UNI_ROUTER),
                    type(uint256).max
                );
                IERC20(underlyingTokens[i]).approve(
                    address(FRAX_ROUTER),
                    type(uint256).max
                );
                IERC20(underlyingTokens[i]).approve(
                    address(CURVE_WSTETH_POOL),
                    type(uint256).max
                );
            }
        }
        for (uint256 i = 0; i < lTokens.length; i++) {
            PreviousReserves[lTokens[i]] = ICERC20(lTokens[i]).totalReserves();
        }
        WETH.approve(address(GLP), type(uint256).max);
        WETH.approve(address(this), type(uint256).max);
        GLP.approve(address(GLP_ROUTER), type(uint256).max);
        SGLP.approve(address(GLP_ROUTER), type(uint256).max);
        PLVGLP.approve(address(PLUTUS_DEPOSITOR), type(uint256).max);

        __Ownable2Step_init();
        __ReentrancyGuard_init();
    }

    /**
     * @notice Utility function to compare strings to each other
     * @return Boolean, true if strings match, false otherwise
     */
    function compareStrings(
        string memory a,
        string memory b
    ) internal pure returns (bool) {
        if (bytes(a).length != bytes(b).length) {
            return false;
        }
        return (keccak256(abi.encodePacked((a))) ==
            keccak256(abi.encodePacked((b))));
    }

    /**
     * @notice Permissioned function to reduce reserves on all markets and send to distributor
     * @param lTokens[] The list of lTokens to draw reserves from
     * @dev Verifies authorization via external Whitelist contract, loops over markets array and
     * @dev reduces reserves according to the amount accrued since the previous withdrawal multiplied
     * @dev by the withdrawMantissa. Swaps using different DEX's/contracts based on the underlying token
     * @dev down to WETH, which is unwrapped into native ETH. The ETH is transferred using sendValue to
     * @dev the distributor contract. After the transfer the hook to initiate rewards distribution is called
     * @dev and the RewardsDistributed event is emitted.
     */
    function withdrawRewards(address[] memory lTokens) external nonReentrant {
        require(
            WHITELIST.isWhitelisted(msg.sender),
            "RewardRouter: UNAUTHORIZED"
        );
        for (uint256 i = 0; i < lTokens.length; i++) {
            uint256 currentReserves = ICERC20(lTokens[i]).totalReserves();
            uint256 previousReserves = PreviousReserves[lTokens[i]];
            uint256 delta = currentReserves - previousReserves;
            uint256 withdrawAmount = (delta * withdrawMantissa) / BASE;
            if (delta == 0 || withdrawAmount == 0) {
                continue;
            }
            require(
                ICERC20(lTokens[i])._reduceReserves(withdrawAmount) == 0,
                "RewardRouter: Withdrawal Failed"
            );
            string memory name = ICERC20(lTokens[i]).symbol();
            if (compareStrings(name, "lplvGLP") && withdrawAmount < 1 ether) {
                continue;
            }
            string memory underlyingSymbol;
            IERC20Extended underlying;
            uint256 minAmountOut;
            if (!compareStrings(name, "lETH")) {
                underlying = IERC20Extended(ICERC20(lTokens[i]).underlying());
                underlyingSymbol = underlying.symbol();
                if (!compareStrings(underlyingSymbol, "plvGLP")) {
                    minAmountOut = Swap.getMinimumSwapAmountOut(
                        underlying,
                        IERC20Extended(address(WETH)),
                        withdrawAmount,
                        (MAX_SLIPPAGE * 3)
                    );
                }
            }
            if (
                compareStrings(underlyingSymbol, "USDC") ||
                compareStrings(underlyingSymbol, "USDT") ||
                compareStrings(underlyingSymbol, "DAI") ||
                compareStrings(underlyingSymbol, "WBTC") ||
                compareStrings(underlyingSymbol, "ARB") ||
                compareStrings(underlyingSymbol, "GMX")
            ) {
                Swap.swapThroughUniswap(
                    address(underlying),
                    address(WETH),
                    withdrawAmount,
                    minAmountOut
                );
            } else if (
                compareStrings(underlyingSymbol, "MAGIC") ||
                compareStrings(underlyingSymbol, "DPX")
            ) {
                Swap.swapThroughSushiswap(
                    address(underlying),
                    address(WETH),
                    withdrawAmount,
                    minAmountOut
                );
            } else if (compareStrings(underlyingSymbol, "FRAX")) {
                Swap.swapThroughFraxswap(
                    address(underlying),
                    address(WETH),
                    withdrawAmount,
                    minAmountOut
                );
            } else if (compareStrings(underlyingSymbol, "plvGLP")) {
                Swap.unwindPlutusPosition();
            } else if (compareStrings(underlyingSymbol, "wstETH")) {
                Swap.swapThroughCurve(withdrawAmount, 0, false);
            } else {
                uint256 ethBalance = address(this).balance;
                Swap.wrapEther(ethBalance);
            }
            uint256 newReserves = ICERC20(lTokens[i]).totalReserves();
            PreviousReserves[lTokens[i]] = newReserves;
        }
        uint256 wethBalance = WETH.balanceOf(address(this));
        require(
            WETH.transferFrom(address(this), DISTRIBUTOR, wethBalance),
            "RewardRouter: WETH Transfer Failed."
        );
        StakingRewardsInterface(DISTRIBUTOR).updateWeeklyRewards(wethBalance);
        emit RewardsDistributed(wethBalance, block.timestamp);
    }

    //**ADMIN FUNCTIONS */

    event DistributorUpdated(address oldDistributor, address newDistributor);
    event WithdrawMantissaUpdated(
        uint256 oldWithdrawMantissa,
        uint256 newWithdrawMantissa
    );

    /**
     * @notice Permissioned function for admins to update the distributor
     * @param newDistributor The distributor address you wish to update to
     */
    function _updateDistributor(address newDistributor) external onlyOwner {
        require(newDistributor != address(0), "Invalid Distributor Address");
        address oldDistributor = DISTRIBUTOR;
        DISTRIBUTOR = newDistributor;
        emit DistributorUpdated(oldDistributor, DISTRIBUTOR);
    }

    /**
     * @notice Permissioned function for admins to update the withdraw mantissa for staking rewards
     * @param newWithdrawMantissa The withdraw mantissa to be applied, must be less than 1 or 100%.
     */
    function _updateWithdrawMantissa(
        uint256 newWithdrawMantissa
    ) external onlyOwner {
        require(newWithdrawMantissa <= BASE, "Invalid Withdraw Mantissa");
        uint256 oldWithdrawMantissa = withdrawMantissa;
        withdrawMantissa = newWithdrawMantissa;
        emit WithdrawMantissaUpdated(oldWithdrawMantissa, newWithdrawMantissa);
    }

    /**
     * @notice Permissioned function for admins to initialize new markets
     * @param newMarkets An array of the new token markets you wish to add
     * @dev new market cannot be a native ether market, it is assumed this market is already initialized
     */
    function _initializeMarkets(
        address[] memory newMarkets
    ) external onlyOwner {
        require(newMarkets.length != 0, "Invalid Address Array");
        for (uint256 i = 0; i < newMarkets.length; i++) {
            require(newMarkets[i] != address(0), "Invalid Market");
            uint256 reserves = ICERC20(newMarkets[i]).totalReserves();
            PreviousReserves[newMarkets[i]] = reserves;
            IERC20 underlyingToken = IERC20(
                ICERC20(newMarkets[i]).underlying()
            );
            underlyingToken.approve(address(SUSHI_ROUTER), type(uint256).max);
            underlyingToken.approve(address(UNI_ROUTER), type(uint256).max);
            underlyingToken.approve(address(FRAX_ROUTER), type(uint256).max);
        }
    }

    /**
     * @notice Permissioned function for admins to withdraw tokens from the contract
     * @param markets An array of the token markets you wish to withdraw
     */
    function _withdraw(address[] memory markets) external onlyOwner {
        require(markets.length != 0, "Invalid Address Array");
        for (uint256 i = 0; i < markets.length; i++) {
            require(markets[i] != address(0), "Invalid Address");
            if (markets[i] == lETH) {
                uint256 ethBalance = address(this).balance;
                (bool sent, ) = msg.sender.call{value: ethBalance}("");
                require(sent, "ETH Transfer failed");
            } else {
                uint256 tokenBalance = IERC20(markets[i]).balanceOf(
                    address(this)
                );
                require(
                    IERC20(markets[i]).transferFrom(
                        address(this),
                        msg.sender,
                        tokenBalance
                    ),
                    "Token Transfer Failed"
                );
            }
        }
    }

    receive() external payable {}
}

