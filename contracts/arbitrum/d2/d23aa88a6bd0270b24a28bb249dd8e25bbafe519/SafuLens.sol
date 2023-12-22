// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.6;
pragma abicoder v2;

import "./IRamsesNfpManager.sol";
import "./IRamsesClFactory.sol";
import "./IRamsesVoter.sol";
import "./IRamsesGaugeV2.sol";
import "./IRamsesV2Pool.sol";
import "./IERC20.sol";

struct ClData {
    uint256 nft_id;
    address token0;
    address token1;
    string symbol0;
    string symbol1;
    uint24 fee;
    address pool_address;
    address gauge_address;
    uint256 pool_liquidity;
    uint256 pool_boostedliq;
    uint256 boostedliq;
    int24 tick;
    int24 tick_lower;
    int24 tick_upper;
    uint128 liquidity;
    uint256 earned;
}

contract SafuLens {
    IRamsesNfpManager public ramsesNfpManager =
        IRamsesNfpManager(0xAA277CB7914b7e5514946Da92cb9De332Ce610EF);
    IRamsesClFactory public ramsesClFactory =
        IRamsesClFactory(0xAA2cd7477c451E703f3B9Ba5663334914763edF8);
    IRamsesVoter public ramsesVoter =
        IRamsesVoter(0xAAA2564DEb34763E3d05162ed3f5C2658691f499);
    address public constant RAM = 0xAAA6C1E32C55A7Bfa8066A6FAE9b42650F262418;

    function initialize() public {
        ramsesNfpManager = IRamsesNfpManager(
            0xAA277CB7914b7e5514946Da92cb9De332Ce610EF
        );
        ramsesClFactory = IRamsesClFactory(
            0xAA2cd7477c451E703f3B9Ba5663334914763edF8
        );
        ramsesVoter = IRamsesVoter(0xAAA2564DEb34763E3d05162ed3f5C2658691f499);
    }

    function nftsOfOwner(address owner) public view returns (uint256[] memory) {
        uint256[] memory nft_ids = new uint256[](
            ramsesNfpManager.balanceOf(owner)
        );
        for (uint256 i = 0; i < nft_ids.length; i++) {
            nft_ids[i] = ramsesNfpManager.tokenOfOwnerByIndex(owner, i);
        }

        return nft_ids;
    }

    function getClData(uint256 nft_id) public view returns (ClData memory) {
        ClData memory clData;

        (
            ,
            ,
            clData.token0,
            clData.token1,
            clData.fee,
            clData.tick_lower,
            clData.tick_upper,
            ,
            ,
            ,
            ,

        ) = ramsesNfpManager.positions(nft_id);

        clData.pool_address = ramsesClFactory.getPool(clData.token0, clData.token1, clData.fee);
        clData.gauge_address = ramsesVoter.gauges(clData.pool_address);
        (clData.liquidity, clData.boostedliq, ) = IRamsesGaugeV2(
            clData.gauge_address
        ).positionInfo(nft_id);

        clData.symbol0 = IERC20(clData.token0).symbol();
        clData.symbol1 = IERC20(clData.token1).symbol();
        clData.pool_liquidity = IRamsesV2Pool(clData.pool_address).liquidity();
        clData.pool_boostedliq = IRamsesV2Pool(clData.pool_address).boostedLiquidity();
        (, clData.tick, , , , , ) = IRamsesV2Pool(clData.pool_address).slot0();
        clData.earned = IRamsesGaugeV2(clData.gauge_address).earned(RAM, nft_id);

        return clData;
    }

    function getClDataBatched(uint256[] memory nft_ids) public view returns (ClData[] memory){
        ClData[] memory clData = new ClData[](nft_ids.length);
        for (uint256 i = 0; i < nft_ids.length; i++) {
            clData[i] = getClData(nft_ids[i]);
        }

        return clData;
    }

    function clDataOfOwner(address owner) public view returns(ClData[] memory) {
        uint256[] memory nft_ids = nftsOfOwner(owner);
        
        return getClDataBatched(nft_ids); 
    }
}

