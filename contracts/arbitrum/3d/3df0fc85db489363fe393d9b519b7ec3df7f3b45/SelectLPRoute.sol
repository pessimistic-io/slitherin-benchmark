// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "./ReentrancyGuard.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./IUniswapV2Factory.sol";
import "./Ownable.sol";
import "./ISwapsUni.sol";
import "./IFarmsUni.sol";
import "./IDepositsBeets.sol";

error SelectLPRoute__DepositOnLPInvalidLPToken();
contract SelectLPRoute is Ownable {
    using SafeERC20 for IERC20;

    address immutable swapsUni;
    address immutable farmsUni;
    address immutable depositsBeets;
    address private nodes;

    modifier onlyAllowed() {
        require(msg.sender == owner() || msg.sender == nodes, 'You must be the owner.');
        _;
    }

    constructor(address farmsUni_, address swapsUni_, address depositsBeets_ ) {
        farmsUni = farmsUni_;
        swapsUni = swapsUni_;
        depositsBeets = depositsBeets_;
    }

    function setNodes(address nodes_) public onlyAllowed {
        nodes = nodes_;
    }

    function depositOnLP(
        bytes32 poolId_,
        address lpToken_,
        uint8 provider_,
        address[] memory tokens_,
        uint256[] memory amounts_,
        uint256 amountOutMin0_,
        uint256 amountOutMin1_) public onlyAllowed returns (uint256[] memory amountsOut, uint256 amountIn, address lpToken, uint256 numTokensOut){
        if (provider_ == 0) { // spookySwap
            IERC20(tokens_[0]).safeTransferFrom(msg.sender, address(this), amounts_[0]);
            IERC20(tokens_[1]).safeTransferFrom(msg.sender, address(this), amounts_[1]);
            _approve(tokens_[0], address(farmsUni), amounts_[0]);
            _approve(tokens_[1], address(farmsUni), amounts_[1]);

            IUniswapV2Router02 router = ISwapsUni(swapsUni).getRouter(tokens_[0], tokens_[1]);
            if (lpToken_ != IUniswapV2Factory(IUniswapV2Router02(router).factory()).getPair(tokens_[0], tokens_[1])) revert  SelectLPRoute__DepositOnLPInvalidLPToken();
            amountsOut = new uint256[](2);
            (amountsOut[0], amountsOut[1], amountIn) = IFarmsUni(farmsUni).addLiquidity(router, tokens_[0], tokens_[1], amounts_[0], amounts_[1], amountOutMin0_, amountOutMin1_);
            lpToken = lpToken_;
            numTokensOut = 2;
        } else { // beets
            IERC20(tokens_[0]).safeTransferFrom(msg.sender, address(this), amounts_[0]);
            _approve(tokens_[0], address(depositsBeets), amounts_[0]);
            (lpToken, amountIn) = IDepositsBeets(depositsBeets).joinPool(poolId_, tokens_, amounts_);
            amountsOut = new uint256[](1);
            amountsOut[0] = amounts_[0];
            numTokensOut = 1;
        }
        IERC20(lpToken).safeTransfer(msg.sender, amountIn);
        }
    function withdrawFromLp(
        bytes32 poolId_,
        address lpToken_,
        uint8 provider_,
        address[] memory tokens_,
        uint256[] memory amountsOutMin_,
        uint256 amount_
    ) public onlyAllowed returns(address tokenDesired, uint256 amountTokenDesired) {
        IERC20(lpToken_).safeTransferFrom(msg.sender, address(this), amount_);
        if (provider_ == 0) { // spookySwap
            _approve(lpToken_, address(farmsUni), amount_);
            amountTokenDesired = IFarmsUni(farmsUni).withdrawLpAndSwap(address(swapsUni), lpToken_, tokens_, amountsOutMin_[0], amount_);
            tokenDesired = tokens_[2];
         } else { // beets
            _approve(lpToken_, address(depositsBeets), amount_);
            amountTokenDesired = IDepositsBeets(depositsBeets).exitPool(poolId_, lpToken_, tokens_, amountsOutMin_, amount_);
            tokenDesired = tokens_[0];
         }
        IERC20(tokenDesired).safeTransfer(msg.sender, amountTokenDesired);
    }

    function depositOnFarmTokens(
        address lpToken_,
        address[] memory tokens_,
        uint256 amount0_,
        uint256 amount1_,
        uint8 provider_
    ) public onlyAllowed returns(uint256 amount0f_, uint256 amount1f_, uint256 lpBal_) {
        IERC20(tokens_[0]).safeTransferFrom(msg.sender, address(this), amount0_);
        IERC20(tokens_[1]).safeTransferFrom(msg.sender, address(this), amount1_);
        if (provider_ == 0) { // spooky
            IUniswapV2Router02 router = ISwapsUni(address(swapsUni)).getRouter(tokens_[0], tokens_[1]);
            _approve(tokens_[0], address(farmsUni), amount0_);
            _approve(tokens_[1], address(farmsUni), amount1_);
            (amount0f_, amount1f_, lpBal_) = IFarmsUni(farmsUni).addLiquidity(router, tokens_[0], tokens_[1], amount0_, amount1_, 0, 0);
        }
        IERC20(lpToken_).safeTransfer(msg.sender, lpBal_);
    }

    function withdrawFromFarm(
        address lpToken_,
        address[] memory tokens_,
        uint256 amountOutMin_,
        uint256 amountLp_,
        uint256 provider_
    ) public onlyAllowed returns (uint256 amountTokenDesired) {
        IERC20(lpToken_).safeTransferFrom(msg.sender, address(this), amountLp_);
        if (provider_ == 0) { // spooky
        _approve(lpToken_, address(farmsUni), amountLp_);
        amountTokenDesired = IFarmsUni(farmsUni).withdrawLpAndSwap(address(swapsUni), lpToken_, tokens_, amountOutMin_, amountLp_);
        }
        IERC20(tokens_[2]).safeTransfer(msg.sender, amountTokenDesired);
    }

    /**
     * @notice Approve of a token
     * @param token_ Address of the token wanted to be approved
     * @param spender_ Address that is wanted to be approved to spend the token
     * @param amount_ Amount of the token that is wanted to be approved.
     */
    function _approve(address token_, address spender_, uint256 amount_) internal {
        IERC20(token_).safeApprove(spender_, 0);
        IERC20(token_).safeApprove(spender_, amount_);
    }
}
