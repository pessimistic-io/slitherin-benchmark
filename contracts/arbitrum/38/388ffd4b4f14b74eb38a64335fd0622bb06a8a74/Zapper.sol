// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "./ERC20.sol";
import "./IERC20.sol";
import "./ERC721.sol";
import "./IERC721.sol";
import "./ERC721Enumerable.sol";
import "./Ownable.sol";
import "./Pausable.sol";
import "./IERC20.sol";
import "./IERC721.sol";
import "./SafeERC20.sol";
import "./InterfaceLibrary.sol";

contract Zapper is Ownable {
    using SafeERC20 for IERC20;

    /*----------  CONSTANTS  --------------------------------------------*/

    uint256 private immutable MAX = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    uint256 private immutable DIVISOR = 1000;

    /*----------  STATE VARIABLES  --------------------------------------*/

    address public factory;
    address public collectionContract;
    uint256 public existingLength;

    /*----------  ERRORS ------------------------------------------------*/

    /*----------  EVENTS ------------------------------------------------*/

    /*----------  MODIFIERS  --------------------------------------------*/

    /*----------  FUNCTIONS  --------------------------------------------*/

    struct ZapParams {
        address gbtForCollection;
        address tokenIn; 
        address tokenOut;
        uint256 amountIn; 
        uint256 amountOut;
        address affiliate;
        bool swapForExact;
        uint256[] ids;
    }

    constructor(
        address _factory,
        address _collection,
        uint256 _existingLength
    ) {
        factory = _factory;
        collectionContract = _collection;
        existingLength = _existingLength;
    }

    function zap(ZapParams memory params) external {
        address user = msg.sender;
        (uint256 index, address gbt, address gnft, , bool allowed) = ICollection(collectionContract).findCollectionByAddress(params.gbtForCollection);
        address base = IGBT(gbt).BASE_TOKEN();

        require(allowed, "!Allowed");

        if (params.tokenIn == base && params.tokenOut == gbt) {
            // BASE -> GBT
            IERC20(base).safeTransferFrom(user, address(this), params.amountIn);
            verifyApproval(gbt, params.amountIn, base);
            if (index < existingLength) {
                IGBT(gbt).buy(params.amountIn, params.amountOut, 0);
            } else {
                IGBT(gbt).buy(params.amountIn, params.amountOut, 0, user, params.affiliate);
            }
        } else if (params.tokenIn == gbt && params.tokenOut == base) {
            // GBT -> BASE
            IERC20(gbt).safeTransferFrom(user, address(this), params.amountIn);
            verifyApproval(gbt, params.amountIn, gbt);
            if (index < existingLength) {
                IGBT(gbt).sell(params.amountIn, params.amountOut, 0);
            } else {
                IGBT(gbt).sell(params.amountIn, params.amountOut, 0, user);
            }
        } else if (params.tokenIn == gbt && params.tokenOut == gnft) {
            // GBT -> GNFT
            IERC20(gbt).safeTransferFrom(user, address(this), params.amountIn);
            verifyApproval(gnft, params.amountIn, gbt);
            if (params.swapForExact) {
                IGNFT(gnft).swapForExact(params.ids);
            } else {
                IGNFT(gnft).swap(params.amountIn);
            }
            uint256 gnftBal = IERC721(gnft).balanceOf(address(this));
            for (uint256 i = 0; i < gnftBal; i++) {
                IERC721(gnft).safeTransferFrom(address(this), user, IGNFT(gnft).tokenOfOwnerByIndex(address(this), 0));
            }
        } else if (params.tokenIn == gnft && params.tokenOut == gbt) {
            // GNFT -> GBT
            for (uint256 i = 0; i < params.ids.length; i++) {
                IERC721(gnft).safeTransferFrom(user, address(this), params.ids[i]);
            }
            if (!ERC721(gnft).isApprovedForAll(address(this), gnft)) {
                ERC721(gnft).setApprovalForAll(gnft, true);
            }
            IGNFT(gnft).redeem(params.ids);
        } else if (params.tokenIn == base && params.tokenOut == gnft) {
            // BASE -> GNFT
            // Transfer BASE to router
            IERC20(base).safeTransferFrom(user, address(this), params.amountIn);
            // Buy GBT with BASE
            verifyApproval(gbt, params.amountIn, base);
            if (index < existingLength) {
                IGBT(gbt).buy(params.amountIn, params.amountOut, 0);
            } else {
                IGBT(gbt).buy(params.amountIn, params.amountOut, 0, user, params.affiliate);
            }
            // Swap GBT for GNFT
            verifyApproval(gnft, IERC20(gbt).balanceOf(address(this)), gbt);
            if (params.swapForExact) {
                IGNFT(gnft).swapForExact(params.ids);
            } else {
                IGNFT(gnft).swap(IERC20(gbt).balanceOf(address(this)) / 1e18 * 1e18);
            }
            uint256 gnftBal = IERC721(gnft).balanceOf(address(this));
            for (uint256 i = 0; i < gnftBal; i++) {
                IERC721(gnft).safeTransferFrom(address(this), user, IGNFT(gnft).tokenOfOwnerByIndex(address(this), 0));
            }
        } else if (params.tokenIn == gnft && params.tokenOut == base) {
            // GNFT -> BASE
            // Transfer GNFT to router
            for (uint256 i = 0; i < params.ids.length; i++) {
                IERC721(gnft).safeTransferFrom(user, address(this), params.ids[i]);
            }
            // Redeem GNFT for GBT
            if (!ERC721(gnft).isApprovedForAll(address(this), gnft)) {
                ERC721(gnft).setApprovalForAll(gnft, true);
            }
            IGNFT(gnft).redeem(params.ids);
            // Sell GBT for BASE
            verifyApproval(gbt, IERC20(gbt).balanceOf(address(this)), gbt);
            if (index < existingLength) {
                IGBT(gbt).sell(IERC20(gbt).balanceOf(address(this)), params.amountOut, 0);
            } else {
                IGBT(gbt).sell(IERC20(gbt).balanceOf(address(this)), params.amountOut, 0, user);
            }
        }
        IERC20(base).safeTransfer(user, IERC20(base).balanceOf(address(this)));
        IERC20(gbt).safeTransfer(user, IERC20(gbt).balanceOf(address(this)));
    }

    function claimAllRewards() external {
        uint256[] memory allCollections = ICollection(collectionContract).allowedCollections();
        for (uint256 i = 0; i < allCollections.length; i++) {
            if (allCollections[i] > existingLength) {
                (address gbt, , address xgbt, ) = IFactory(factory).deployInfo(allCollections[i]);
                if (IXGBT(xgbt).earned(msg.sender, gbt) > 0) {
                    IXGBT(xgbt).getReward(address(msg.sender));
                }
            } 
        }
    }

    /*----------  RESTRICTED FUNCTIONS  ---------------------------------*/

    function verifyApproval(address spender, uint256 amount, address token) internal {
        if (IERC20(token).allowance(address(this), spender) < amount) {
            IERC20(token).safeApprove(spender, MAX);
        }
    }

    /*----------  VIEW FUNCTIONS  ---------------------------------------*/

    function quoteBuyBaseIn(address gbt, uint256 fee, uint256 input, uint256 slippageTolerance, uint256 autoSlippage) external view returns (uint256 output, uint256 slippage, uint256 minOutput, uint256 autoMinOutput) {
        uint256 feeBASE = input * fee / DIVISOR;
        uint256 oldReserveBASE = IGBT(gbt).reserveVirtualBASE() + IGBT(gbt).reserveRealBASE();
        uint256 newReserveBASE = oldReserveBASE + input - feeBASE;
        uint256 oldReserveGBT = IGBT(gbt).reserveGBT();
        uint256 currentPrice = IGBT(gbt).currentPrice();
        output = oldReserveGBT - (oldReserveBASE * oldReserveGBT / newReserveBASE);
        slippage = 100 * (1e18 - (output * currentPrice / input));
        minOutput = (input * 1e18 / currentPrice) * slippageTolerance / DIVISOR;
        autoMinOutput = (input * 1e18 / currentPrice) * ((DIVISOR * 1e18) - ((slippage + autoSlippage) * 10)) / (DIVISOR * 1e18);
    }

    function quoteBuyGBTOut(address gbt, uint256 fee, uint256 input, uint256 slippageTolerance, uint256 autoSlippage) public view returns (uint256 output, uint256 slippage, uint256 minOutput, uint256 autoMinOutput) {
        uint256 oldReserveBASE = IGBT(gbt).reserveVirtualBASE() + IGBT(gbt).reserveRealBASE();
        output = DIVISOR * ((oldReserveBASE * IGBT(gbt).reserveGBT() / (IGBT(gbt).reserveGBT() - input)) - oldReserveBASE) / (DIVISOR - fee);
        slippage = 100 * (1e18 - (input * IGBT(gbt).currentPrice() / output));
        minOutput = input * slippageTolerance / DIVISOR;
        autoMinOutput = input * ((DIVISOR * 1e18) - ((slippage + autoSlippage) * 10)) / (DIVISOR * 1e18);
    }

    function quoteSellGBTIn(address gbt, uint256 fee, uint256 input, uint256 slippageTolerance, uint256 autoSlippage) public view returns (uint256 output, uint256 slippage, uint256 minOutput, uint256 autoMinOutput) {
        uint256 oldReserveGBT = IGBT(gbt).reserveGBT();
        uint256 newReserveGBT = oldReserveGBT + input - (input * fee / DIVISOR);
        uint256 oldReserveBASE = IGBT(gbt).reserveVirtualBASE() + IGBT(gbt).reserveRealBASE();
        
        output = oldReserveBASE - (oldReserveBASE * oldReserveGBT / newReserveGBT);
        slippage = 100 * (1e18 - (output * 1e18 / (input * IGBT(gbt).currentPrice() / 1e18)));
        minOutput = input * IGBT(gbt).currentPrice() /1e18 * slippageTolerance / DIVISOR;
        autoMinOutput = input * IGBT(gbt).currentPrice() /1e18 * ((DIVISOR * 1e18) - ((slippage + autoSlippage) * 10)) / (DIVISOR * 1e18);
    }

    function quoteSellBaseOut(address gbt, uint256 fee, uint256 input, uint256 slippageTolerance, uint256 autoSlippage) external view returns (uint256 output, uint256 slippage, uint256 minOutput, uint256 autoMinOutput) {
        uint256 oldReserveBASE = IGBT(gbt).reserveVirtualBASE() + IGBT(gbt).reserveRealBASE();
        output = DIVISOR * ((oldReserveBASE * IGBT(gbt).reserveGBT() / (oldReserveBASE - input)) - IGBT(gbt).reserveGBT()) / (DIVISOR - fee);
        slippage = 100 * (1e18 - (input * 1e18 / (output * IGBT(gbt).currentPrice() / 1e18)));
        minOutput = input * slippageTolerance / DIVISOR;
        autoMinOutput = input * ((DIVISOR * 1e18) - ((slippage + autoSlippage) * 10)) / (DIVISOR * 1e18);
    }

    function quoteBASEtoNFT(address gbt, uint256 gbtFee, uint256 input, uint256 slippageTolerance, uint256 autoSlippage) external view returns (uint256 output, uint256 slippage, uint256 autoOutput) {
        (output, slippage, , ) = quoteBuyGBTOut(gbt, gbtFee, input, slippageTolerance, autoSlippage);
        output = output * DIVISOR / slippageTolerance;
        autoOutput = output * ((DIVISOR * 1e18) + (autoSlippage * 10)) / (DIVISOR * 1e18);
    }

     function quoteNFTtoBASE(address gbt, uint256 gbtFee, uint256 input, uint256 slippageTolerance, uint256 autoSlippage) external view returns (uint256 output, uint256 slippage, uint256 autoOutput) {
        (, , address gnft, ,) = ICollection(collectionContract).findCollectionByAddress(gbt);
        uint256 gbtToSell = input * (DIVISOR - IGNFT(gnft).bFee()) / DIVISOR;
        (output, slippage, , autoOutput) = quoteSellGBTIn(gbt, gbtFee, gbtToSell, slippageTolerance, autoSlippage);
    }

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) public view returns (bytes4) {
        return IERC721Receiver(address(this)).onERC721Received.selector;
    }


}
