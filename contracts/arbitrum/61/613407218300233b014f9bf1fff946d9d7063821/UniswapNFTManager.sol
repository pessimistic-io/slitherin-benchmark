// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {ERC20, SafeTransferLib} from "./SafeTransferLib.sol";

import {Borrower, IManager} from "./Borrower.sol";
import {Factory} from "./Factory.sol";

import {INonfungiblePositionManager as INFTManager} from "./INonfungiblePositionManager.sol";

contract UniswapNFTManager is IManager {
    using SafeTransferLib for ERC20;

    Factory public immutable FACTORY;

    INFTManager public immutable NFT_MANAGER;

    constructor(Factory factory, INFTManager nftManager) {
        FACTORY = factory;
        NFT_MANAGER = nftManager;
    }

    function callback(bytes calldata data) external override returns (uint144 positions) {
        Borrower borrower = Borrower(msg.sender);

        // The ID of the NFT to which liquidity will be added/removed
        uint256 tokenId;
        // The position's lower tick
        int24 lower;
        // The position's upper tick
        int24 upper;
        // The change in the NFT's liquidity. Negative values move NFT-->Borrower, positives do the opposite
        int128 liquidity;
        (tokenId, lower, upper, liquidity, positions) = abi.decode(data, (uint256, int24, int24, int128, uint144));

        // move position from NonfungiblePositionManager to Borrower
        if (liquidity < 0) {
            // safety checks since this contract will be approved to manager users' positions
            {
                require(FACTORY.isBorrower(msg.sender));
                (address owner, , ) = borrower.slot0();
                require(owner == NFT_MANAGER.ownerOf(tokenId));
            }

            _withdrawFromNFT(tokenId, uint128(-liquidity), msg.sender);
            borrower.uniswapDeposit(lower, upper, uint128(-liquidity));
        }
        // move position from Borrower to NonfungiblePositionManager (position must exist already)
        else {
            ERC20 token0 = borrower.TOKEN0();
            ERC20 token1 = borrower.TOKEN1();

            (uint256 burned0, uint256 burned1, , ) = borrower.uniswapWithdraw(lower, upper, uint128(liquidity));
            token0.safeTransferFrom(msg.sender, address(this), burned0);
            token1.safeTransferFrom(msg.sender, address(this), burned1);

            token0.safeApprove(address(NFT_MANAGER), burned0);
            token1.safeApprove(address(NFT_MANAGER), burned1);
            NFT_MANAGER.increaseLiquidity(
                INFTManager.IncreaseLiquidityParams({
                    tokenId: tokenId,
                    amount0Desired: burned0,
                    amount1Desired: burned1,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp
                })
            );
        }
    }

    function _withdrawFromNFT(uint256 tokenId, uint128 liquidity, address recipient) private {
        NFT_MANAGER.decreaseLiquidity(
            INFTManager.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );

        NFT_MANAGER.collect(
            INFTManager.CollectParams({
                tokenId: tokenId,
                recipient: recipient,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
    }
}

