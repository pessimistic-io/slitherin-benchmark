// SPDX-License-Identifier: MIT
// Based on Uniswap V2 @ https://github.com/Uniswap/v2-core/releases/tag/v1.0.1

pragma solidity =0.5.16;

import "./UniswapV2ERC20.sol";

/**
 * @title Sec-urity Gensler Meme Coin
 * @author The Security Team
 * @notice The goal of this coin is to satirize institutions in their futile war against the crypto space
 * 
 * Supply Allocation
 * - 20% Team Supply (divided in 3 years on a weekly basis)
 * - 10% Marketing
 * - 10% DAO Fund
 * - 10% Liquidity
 * - 50% LP Farm Community
 * 
 * Don't trust, verify:
 * Project: https://github.com/meme-factory/Sec-urity-Gensler
 * White Paper: https://github.com/meme-factory/Sec-urity-Gensler/blob/main/white-paper.md
 * Launchpad: Meme Factory https://github.com/meme-factory
 *
 * We are the army!
 * We are the crypto army!!
 * We are the meme crypto army!!!
 */
contract GenslerToken is UniswapV2ERC20 {
    string public constant name = 'Sec-urity Gensler';
    string public constant symbol = 'GENSLER';

    address public constant TEAM_SUPPLY_VAULT = 0x91a0477de2Ec316f01872A8376e3191D115873Ef;
    address public constant MARKETING_VAULT = 0x4db353F92a268a3F3BcDcD031808492816e0F00d;
    address public constant DAO_FUND_VAULT = 0x38c3A5B0cb7c7F4fc3ef9Fd94868e95dcf83Be51;
    address public constant LIQUIDITY_VAULT = 0x283b195AB4f7A7B813F95304120f146E9B94C2D1;
    address public constant LP_FARM_COMMUNITY_VAULT = 0xa9C4C79FDFa8Ff63735d3129C9B3041CE83030AA;
    
    uint256 public constant TEAM_SUPPLY_ALLOCATION = 84_000_000_000 ether;
    uint256 public constant MARKETING_ALLOCATION = 42_000_000_000 ether;
    uint256 public constant DAO_FUND_ALLOCATION = 42_000_000_000 ether;
    uint256 public constant LIQUIDITY_ALLOCATION = 42_000_000_000 ether;
    uint256 public constant LP_FARM_COMMUNITY_ALLOCATION = 210_000_000_000 ether;
    uint256 public constant GENSLER_TOTAL_SUPPLY_ALLOCATION = 420_000_000_000 ether;

    constructor() public {
        require(
            TEAM_SUPPLY_ALLOCATION +
            MARKETING_ALLOCATION +
            DAO_FUND_ALLOCATION +
            LIQUIDITY_ALLOCATION +
            LP_FARM_COMMUNITY_ALLOCATION ==
            GENSLER_TOTAL_SUPPLY_ALLOCATION
        );

        _mint(TEAM_SUPPLY_VAULT, TEAM_SUPPLY_ALLOCATION);
        _mint(MARKETING_VAULT, MARKETING_ALLOCATION);
        _mint(DAO_FUND_VAULT, DAO_FUND_ALLOCATION);
        _mint(LIQUIDITY_VAULT, LIQUIDITY_ALLOCATION);
        _mint(LP_FARM_COMMUNITY_VAULT, LP_FARM_COMMUNITY_ALLOCATION);
    }
}

