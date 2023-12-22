// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {LPVault, FixedPointMath, OneInchZapLib, I1inchAggregationRouterV4, SafeERC20, IERC20} from "./LPVault.sol";

contract BearLPVault is LPVault {
    using SafeERC20 for IERC20;
    using OneInchZapLib for I1inchAggregationRouterV4;
    using FixedPointMath for uint256;

    IERC20 private _2Crv;

    constructor(
        address _depositToken,
        address _storage,
        string memory _name,
        uint256 _riskPercentage,
        uint256 _feePercentage,
        address _feeReceiver,
        address payable _router,
        uint256 _cap,
        address _farm
    ) LPVault(_depositToken, _storage, _name, _riskPercentage, _feePercentage, _feeReceiver, _router, _cap, _farm) {
        vaultType = VaultType.BEAR;
        _2Crv = IERC20(address(OneInchZapLib.crv2));
    }

    /**
     * @notice Removes liquidity and swap tokens to `2Crv` and transfer the tokens to the strategy
     * contract
     * @param _minTokenOutputs The minimum amount of tokens to receive when removing liquidity
     * @param _min2Crv The minimum amount of `2Crv` to receive from swapping tokens on the LP pair
     * @param _intermediateToken The stable coin to use to mint `2Crv` (USDC | USDT)
     * @param _swapParams The parameters for swapping the pair tokens to _intermediateToken on 1Inch
     */
    function borrow(
        uint256[2] calldata _minTokenOutputs,
        uint256 _min2Crv,
        address _intermediateToken,
        OneInchZapLib.SwapParams[2] calldata _swapParams
    ) external onlyRole(STRATEGY) returns (uint256[2] memory) {
        if (paused) {
            revert VAULT_PAUSED();
        }
        // Can only borrow once per epoch
        if (borrowed) {
            revert ALREADY_BORROWED();
        }

        if (
            _swapParams[0].desc.dstReceiver != address(this) || _swapParams[1].desc.dstReceiver != address(this)
                || _swapParams[0].desc.minReturnAmount == 0 || _swapParams[1].desc.minReturnAmount == 0
        ) {
            revert FORBIDDEN_SWAP_RECEIVER();
        }

        IERC20 pair = IERC20(address(depositToken));

        // To store amounts
        uint256[2] memory amounts;

        uint256 tokenBalance = pair.balanceOf(address(this));
        // Store LP amount
        amounts[0] = (tokenBalance + _getStakedAmount()).mulDivDown(riskPercentage, ACCURACY);
        if (tokenBalance < amounts[0]) {
            _unstake(amounts[0] - tokenBalance);
        }
        borrowed = true;

        // Store 2Crv amount
        amounts[1] = router.zapOutTo2crv(
            address(pair),
            amounts[0],
            _minTokenOutputs[0],
            _minTokenOutputs[1],
            _min2Crv,
            _intermediateToken,
            _swapParams[0],
            _swapParams[1]
        );

        _2Crv.transfer(msg.sender, amounts[1]);

        emit Borrowed(msg.sender, amounts[0]);

        return amounts;
    }

    /**
     * @notice Used for the strategy contract to repay the LP tokens that were borrowed. The 2Crv
     * tokens are transferred from the strategy to the vault and then zapped in to the LP token
     * @param _minOutputs [0] -> minToken0Amount | [1] -> minToken1Amount when swapping
     * @param _minLpTokens min number of lp tokens resulting of the zap in
     * @param _swapParams The parameters for swapping the 2crv to token0 and token1 on 1Inch
     */
    function repay(
        uint256[2] calldata _minOutputs,
        uint256 _minLpTokens,
        address _intermediateToken,
        OneInchZapLib.SwapParams[2] calldata _swapParams
    ) external onlyRole(STRATEGY) returns (uint256) {
        if (
            _swapParams[0].desc.dstReceiver != address(this) || _swapParams[1].desc.dstReceiver != address(this)
                || _swapParams[0].desc.minReturnAmount == 0 || _swapParams[1].desc.minReturnAmount == 0
        ) {
            revert FORBIDDEN_SWAP_RECEIVER();
        }

        IERC20 _2CrvToken = _2Crv;

        uint256 amount = _2CrvToken.balanceOf(msg.sender);
        _2CrvToken.transferFrom(msg.sender, address(this), amount);

        return router.zapInFrom2Crv(
            _swapParams[0],
            _swapParams[1],
            address(depositToken),
            amount,
            _minOutputs[0],
            _minOutputs[1],
            _minLpTokens,
            _intermediateToken
        );
    }
}

