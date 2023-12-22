//SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

import "./Interfaces.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./Whitelist.sol";
import "./Swap.sol";

//TODO: Add admin functions ?

contract RewardsRouter is RouterConstants, Initializable, Swap, ReentrancyGuardUpgradeable {
    uint256 public withdrawMantissa;
    Whitelist public WHITELIST;
    address public DISTRIBUTOR;
    uint256 public MAX_SLIPPAGE;

    using SafeERC20Upgradeable for IERC20;

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
                IERC20(underlyingTokens[i]).approve(address(SUSHI_ROUTER), type(uint256).max);
                IERC20(underlyingTokens[i]).approve(address(UNI_ROUTER), type(uint256).max);
                IERC20(underlyingTokens[i]).approve(address(FRAX_ROUTER), type(uint256).max);
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
    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        if (bytes(a).length != bytes(b).length) {
            return false;
        }
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
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
        require(WHITELIST.isWhitelisted(msg.sender), "RewardRouter: UNAUTHORIZED");
        for (uint256 i = 0; i < lTokens.length; i++) {
            uint256 currentReserves = ICERC20(lTokens[i]).totalReserves();
            uint256 previousReserves = PreviousReserves[lTokens[i]];
            uint256 delta = currentReserves - previousReserves;
            uint256 withdrawAmount = (delta * withdrawMantissa) / BASE;
            require(ICERC20(lTokens[i])._reduceReserves(withdrawAmount) == 0, "RewardRouter: Withdrawal Failed");
            IERC20Extended underlying = IERC20Extended(ICERC20(lTokens[i]).underlying());
            string memory underlyingSymbol = underlying.symbol();
            uint256 minAmountOut = Swap.getMinimumSwapAmountOut(
                underlying,
                IERC20Extended(address(WETH)),
                withdrawAmount,
                MAX_SLIPPAGE
            );
            if (
                compareStrings(underlyingSymbol, "USDC") ||
                compareStrings(underlyingSymbol, "USDT") ||
                compareStrings(underlyingSymbol, "DAI") ||
                compareStrings(underlyingSymbol, "WBTC") ||
                compareStrings(underlyingSymbol, "ARB")
            ) {
                Swap.swapThroughUniswap(address(underlying), address(WETH), withdrawAmount, minAmountOut);
            } else if (compareStrings(underlyingSymbol, "MAGIC") || compareStrings(underlyingSymbol, "DPX")) {
                Swap.swapThroughSushiswap(address(underlying), address(WETH), withdrawAmount, minAmountOut);
            } else if (compareStrings(underlyingSymbol, "FRAX")) {
                Swap.swapThroughFraxswap(address(underlying), address(WETH), withdrawAmount, minAmountOut);
            } else if (compareStrings(underlyingSymbol, "plvGLP")) {
                Swap.unwindPlutusPosition();
            } else {
                uint256 ethBalance = address(this).balance;
                Swap.wrapEther(ethBalance);
            }
            uint256 wethBalance = WETH.balanceOf(address(this));
            require(WETH.transferFrom(address(this), DISTRIBUTOR, wethBalance), "RewardRouter: WETH Transfer Failed.");
            StakingRewardsInterface(DISTRIBUTOR).updateWeeklyRewards(wethBalance);
            emit RewardsDistributed(wethBalance, block.timestamp);
        }
    }

    //**ADMIN FUNCTIONS */

    event DistributorUpdated(address oldDistributor, address newDistributor);

    function _updateDistributor(address newDistributor) external onlyOwner {
        require(newDistributor != address(0), "Invalid Distributor Address");
        address oldDistributor = DISTRIBUTOR;
        DISTRIBUTOR = newDistributor;
        emit DistributorUpdated(oldDistributor, DISTRIBUTOR);
    }
    //any admin functions required? Or should this really be handled via proxy?
}

