// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;
import {INonfungiblePositionManager} from "./INonfungiblePositionManager.sol";
import {ISwapRouter} from "./ISwapRouter.sol";


 contract UniManager{
     // Uniswap convenience contract for single-tx liquidity burning - intended for use with a specific python application

     struct PositionInfo {
         uint128 liquidity;
         uint128 tokensOwed0;
         uint128 tokensOwed1;
     }

    address payable owner;
    address managerAddress;
    INonfungiblePositionManager posManager;

    constructor(address _managerAddress)  {
        owner = payable(msg.sender);
        // managerAddress = _managerAddress;
        posManager = INonfungiblePositionManager(_managerAddress);
    }

 function getPosition(uint posID) public returns (PositionInfo memory) {
        // Call the positions() function using low-level assembly to retrieve only the value of "liquidity"
        // (for stack-depth reasons)
        (bool success, bytes memory data) = address(posManager).call(
            abi.encodeWithSignature("positions(uint256)", posID)
        );
        
        require(success, "Call to positions failed");

        uint128 liquidity;
        uint128 tokensOwed0;
        uint128 tokensOwed1;

        assembly {
            // Slice the 9th 32-byte chunk (starting from 0) from the return data
            liquidity := mload(add(data, 0x100))
            tokensOwed0 := mload(add(data, 0x160))
            tokensOwed1 := mload(add(data, 0x180))
      
        }
        return PositionInfo(liquidity, tokensOwed0, tokensOwed1);
    }

    function burnPosition(uint posID, uint128 liquidity) public returns(bool) {
        // Decrease liquidity AND collect accrued fees in one tx

        // Grab the user's liquidity position NFT
        posManager.safeTransferFrom(msg.sender, address(this), posID);

        INonfungiblePositionManager.DecreaseLiquidityParams memory dparams;
        INonfungiblePositionManager.CollectParams memory cparams;

        dparams.tokenId = posID;
        dparams.amount0Min = 0;
        dparams.amount1Min = 0;
        dparams.deadline = block.timestamp+60;
        dparams.liquidity = liquidity;
        uint256 tokensBurned0; uint256 tokensBurned1;
        // Burn liquidity
        (tokensBurned0, tokensBurned1) = posManager.decreaseLiquidity(dparams);

        // Collect burned tokens
        PositionInfo memory position = this.getPosition(posID);
        cparams.amount0Max = uint128(tokensBurned0) + position.tokensOwed0;
        cparams.amount1Max = uint128(tokensBurned1) + position.tokensOwed1;
        cparams.tokenId = posID;
        cparams.recipient = msg.sender;
        posManager.collect(cparams);      

        // Either transfer NFT back to user or delete it if it's got 0 liquidity
        if(position.liquidity != 0) {
            posManager.safeTransferFrom(address(this), msg.sender, posID);
        }
        else {
            posManager.burn(posID);
        }
        return true;
    }

    function onERC721Received(
    address _operator,
    address _from,
    uint256 _tokenId,
    bytes calldata _data) external returns (bytes4) {
        return 0x150b7a02;
    }
 }

