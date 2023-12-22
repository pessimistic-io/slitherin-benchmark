// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {ISwapRouter} from "./ISwapRouter.sol";

import {Owned} from "./Owned.sol";
import {ERC721} from "./ERC721.sol";
import {SafeERC20, IERC20} from "./SafeERC20.sol";

// import "forge-std/console2.sol";

contract UniswapRouterAccessor is ERC721, Owned {
    using SafeERC20 for IERC20;

    ISwapRouter public router;
    IERC20 public weth;
    IERC20 public usdc;
    uint24 public fee;
    uint256 public buyUsdcAmount;
    uint256 public constant tokenId = 1;
    bool public hasPosition;

    constructor(
        address _router,
        address _weth,
        address _usdc
    ) ERC721("UniswapRouterAccessor", "URA") Owned(msg.sender) {
        //set parameters
        fee = 3000;
        buyUsdcAmount = 2000 * 1e6;
        hasPosition = false;
        //set addresses
        router = ISwapRouter(_router);
        weth = IERC20(_weth);
        usdc = IERC20(_usdc);
        //approve
        weth.safeApprove(_router, type(uint256).max);
        usdc.safeApprove(_router, type(uint256).max);
        //mint
        _mint(msg.sender, tokenId);
    }

    /* ========== OWNERS FUNCTIONS ========== */
    function setFee(uint24 _fee) external onlyOwner {
        fee = _fee;
    }

    function setBuyUsdcAmount(uint256 _buyUsdcAmount) external onlyOwner {
        buyUsdcAmount = _buyUsdcAmount;
    }

    function buy(uint256 _amountOutMinimum, uint256 _deadline) external onlyOwner returns (uint256) {
        hasPosition = true;
        return _swap(true, buyUsdcAmount, _amountOutMinimum, _deadline);
    }

    //sell all weth
    function sell(uint256 _amountOutMinimum, uint256 _deadline) external onlyOwner returns (uint256) {
        hasPosition = false;
        return _swap(false, weth.balanceOf(address(this)), _amountOutMinimum, _deadline);
    }

    /* ========== NFTOWNERS FUNCTIONS ========== */
    function deposit(uint256 _amount) external {
        //only nft owner
        _onlyNftOwner();
        usdc.safeTransferFrom(msg.sender, address(this), _amount);
    }

    function withdraw(uint256 _amount) external {
        //only nft owner
        _onlyNftOwner();
        usdc.safeTransfer(msg.sender, _amount);
    }

    //emergency withdraw
    function withdrawWeth(uint256 _amount) external {
        //only nft owner
        _onlyNftOwner();
        weth.safeTransfer(msg.sender, _amount);
    }

    /* ========== INTERNAL FUNCTIONS ========== */
    function _swap(
        bool _isBuy,
        uint256 _amountIn,
        uint256 _amountOutMinimum,
        uint256 _deadline
    ) internal returns (uint256) {
        //check _amountOutMinimum
        require(_amountOutMinimum > 0, "_amountOutMinimum must be greater than 0");

        (address _tokenIn, address _tokenOut) = _isBuy
            ? (address(usdc), address(weth))
            : (address(weth), address(usdc));

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: _tokenIn,
            tokenOut: _tokenOut,
            fee: fee,
            recipient: address(this),
            deadline: _deadline,
            amountIn: _amountIn,
            amountOutMinimum: _amountOutMinimum,
            sqrtPriceLimitX96: 0
        });
        return router.exactInputSingle(params);
    }

    function _onlyNftOwner() internal view {
        require(msg.sender == ownerOf(tokenId), "only nft owner");
    }

    /* ========== UNUSED FUNCTIONS ========== */
    //override
    function tokenURI(uint256) public pure override returns (string memory) {
        return "";
    }
}

