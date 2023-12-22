//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.18;

import {ILockdropPhase1, LockingToken, IUniswapV2Pair, IUniswapV2Router02} from "./ILockdropPhase1.sol";
import {IUniswapV2Factory} from "./IUniswapV2Factory.sol";
import {IChronosRouter} from "./IChronosRouter.sol";
import {ILockdropPhase1Helper} from "./ILockdropPhase1Helper.sol";
import {HomoraMath, SafeMath} from "./HomarMath.sol";
import {IAccessControlHolder, IAccessControl} from "./IAccessControlHolder.sol";

import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";

/**
 * @title LockdropPhase1Helper
 * Implementation of ILockdropPhase1Helper
 */

contract LockdropPhase1Helper is ILockdropPhase1Helper, IAccessControlHolder {
    using SafeERC20 for IERC20;
    using HomoraMath for uint256;
    using SafeMath for uint256;

    bytes32 public constant LOCKDROP = keccak256("LOCKDROP");
    error OnyLockdrop();

    IAccessControl public immutable override acl;

    /**
     * @notice Checks the sender gas LOCKDROP role.
     * @dev Reverts with OnloLockdrop if the sender does not have role.
     */
    modifier onlyLockdrop() {
        if (!acl.hasRole(LOCKDROP, msg.sender)) {
            revert OnyLockdrop();
        }
        _;
    }

    constructor(IAccessControl acl_) {
        acl = acl_;
    }

    /**
     * @inheritdoc ILockdropPhase1Helper
     */
    function removeLiquidity(
        LockingToken memory token,
        uint256 min0,
        uint256 min1,
        uint256 deadline
    ) external onlyLockdrop {
        IUniswapV2Pair pair = IUniswapV2Pair(token.token);
        uint256 balance = pair.balanceOf(address(this));
        address token0 = pair.token0();
        address token1 = pair.token1();
        IERC20(token.token).forceApprove(token.router, balance);

        if (token.isChronos) {
            _removeOnChronos(
                token,
                token0,
                token1,
                balance,
                min0,
                min1,
                msg.sender,
                deadline
            );
        } else {
            _remove(
                token,
                token0,
                token1,
                balance,
                min0,
                min1,
                msg.sender,
                deadline
            );
        }
    }

    /**
     * @notice Function removes liquidity on chronos type of dex.
     * @param token LP token.
     * @param token0 Token0 of the pair.
     * @param token1 Token1 of the pair.
     * @param balance Balance of token.
     * @param min0 Minimal amount of token0.
     * @param min1 Minimal amount of token1.
     * @param to Address where tokens should go.
     * @param deadline Deadline to execute.
     */
    function _removeOnChronos(
        LockingToken memory token,
        address token0,
        address token1,
        uint256 balance,
        uint256 min0,
        uint256 min1,
        address to,
        uint256 deadline
    ) internal {
        IChronosRouter(token.router).removeLiquidity(
            token0,
            token1,
            token.isStable,
            balance,
            min0,
            min1,
            to,
            deadline
        );
    }

    /**
     * @notice Function removes liquidity on chronos type of dex.
     * @param token LP token.
     * @param token0 Token0 of the pair.
     * @param token1 Token1 of the pair.
     * @param balance Balance of token.
     * @param min0 Minimal amount of token0.
     * @param min1 Minimal amount of token1.
     * @param to Address where tokens should go.
     * @param deadline Deadline to execute.
     */
    function _remove(
        LockingToken memory token,
        address token0,
        address token1,
        uint256 balance,
        uint256 min0,
        uint256 min1,
        address to,
        uint256 deadline
    ) internal {
        IUniswapV2Router02(token.router).removeLiquidity(
            token0,
            token1,
            balance,
            min0,
            min1,
            to,
            deadline
        );
    }

    /**
     * @notice Function returns price of the the LP token.
     * @param token LPToken.
     * @param tokenAAddress Address of token A.
     * @param tokenAPrice  Amount of wei ETH * 2**112.
     * @param tokenBPrice Amount of wei ETH * 2**112.
     * @return uint256 Price in wei ETH * 2**112.
     */
    function getPrice(
        address token,
        address tokenAAddress,
        uint256 tokenAPrice,
        uint256 tokenBPrice
    ) external view returns (uint256) {
        IUniswapV2Pair pair = IUniswapV2Pair(token);
        uint256 totalSupply = pair.totalSupply();
        (uint256 r0, uint256 r1, ) = pair.getReserves();
        (uint256 px0, uint256 px1) = pair.token0() == tokenAAddress
            ? (tokenAPrice, tokenBPrice)
            : (tokenBPrice, tokenAPrice);

        uint sqrtK = HomoraMath.sqrt(r0.mul(r1)).fdiv(totalSupply);
        return
            sqrtK
                .mul(2)
                .mul(HomoraMath.sqrt(px0))
                .div(2 ** 56)
                .mul(HomoraMath.sqrt(px1))
                .div(2 ** 56);
    }
}

