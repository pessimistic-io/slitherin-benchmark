// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "./IRamsesNfpManager.sol";
import "./IRamsesClFactory.sol";
import "./IRamsesVoter.sol";
import "./IRamsesGaugeV2.sol";
import "./IRamsesV2Pool.sol";
import "./ERC20.sol";


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
    IRamsesNfpManager public ramsesNfpManager;
    IRamsesClFactory public ramsesClFactory;
    IRamsesVoter public ramsesVoter;
    address public constant RAM = 0xAAA6C1E32C55A7Bfa8066A6FAE9b42650F262418;

    function initialize() public {
        ramsesNfpManager = IRamsesNfpManager(0xAA277CB7914b7e5514946Da92cb9De332Ce610EF);
        ramsesClFactory = IRamsesClFactory(0xAA2cd7477c451E703f3B9Ba5663334914763edF8);
        ramsesVoter = IRamsesVoter(0xAAA2564DEb34763E3d05162ed3f5C2658691f499);
    }

    function getClData(uint256 nft_id) public view returns (ClData memory) {
        (
        ,
        ,
    address token0,
    address token1,
    uint24 fee,
    int24 tickLower,
    int24 tickUpper,
        ,
        ,
        ,
        ,
        ) = ramsesNfpManager.positions(nft_id);

        ClData memory clData;

        address pool_address = ramsesClFactory.getPool(token0, token1, fee);
        address gauge_address = ramsesVoter.gauges(pool_address);
        clData.nft_id = nft_id;
        clData.token0 = token0;
        clData.token1 = token1;
        clData.pool_address = pool_address;
        clData.gauge_address = gauge_address;
        clData.fee = fee;
        clData.tick_lower = tickLower;
        clData.tick_upper = tickUpper;
        clData.symbol0 = ERC20(token0).symbol();
        clData.symbol1 = ERC20(token1).symbol();

        (uint128 liquidity, uint128 boostedliq, ) = IRamsesGaugeV2(
            gauge_address
        ).positionInfo(nft_id);

        clData.liquidity = liquidity;
        clData.boostedliq = boostedliq;
        clData.pool_liquidity = IRamsesV2Pool(pool_address).liquidity();
        clData.pool_boostedliq = IRamsesV2Pool(pool_address).boostedLiquidity();
        (, int24 tick, , , , , ) = IRamsesV2Pool(pool_address).slot0();
        clData.tick = tick;

        clData.earned = IRamsesGaugeV2(gauge_address).earned(RAM, nft_id);

        return clData;
    }
}


