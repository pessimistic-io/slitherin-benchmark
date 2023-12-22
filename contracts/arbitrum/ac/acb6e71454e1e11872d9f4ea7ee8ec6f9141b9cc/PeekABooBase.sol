// SPDX-License-Identifier: MIT LICENSE
pragma solidity ^0.8.0;

import "./IERC20Upgradeable.sol";
import "./IPeekABoo.sol";
import "./ITraits.sol";
import "./ILevel.sol";
import "./IBOO.sol";
import "./IStakeManager.sol";
import "./InGame.sol";

contract PeekABooBase {
    uint256 public MAX_PHASE1_TOKENS;
    uint256 public MAX_PHASE2_TOKENS;
    uint256 public MAX_NUM_PHASE1_GHOSTS;
    uint256 public MAX_NUM_PHASE1_BUSTERS;
    uint256 public MAX_NUM_PHASE2_GHOSTS;
    uint256 public MAX_NUM_PHASE2_BUSTERS;
    uint256 public phase2Price;
    uint256 public phase2PriceRate;
    // number of tokens have been minted so far
    uint256 public phase1Minted;
    uint256 public phase2Minted;
    uint256 public communityNonce;
    uint256 public traitPriceRate;
    uint256 public abilityPriceRate;

    // mapping from tokenId to a struct containing the token's traits
    mapping(uint256 => IPeekABoo.PeekABooTraits) public tokenTraits;
    mapping(uint256 => bool[6]) public boughtAbilities;
    // tokenId => boughtTraitCountByRarity [common,uncommon,...]
    mapping(uint256 => uint256[4]) public boughtTraitCount;
    mapping(uint256 => IPeekABoo.GhostMap) public ghostMaps;
    mapping(address => uint256) public whitelist;

    // reference to $IBOO for burning on mint
    IBOO public boo;
    IERC20Upgradeable public magic;
    ITraits public traits;
    ILevel public level;
    InGame public ingame;
    IStakeManager public stakeManager;

    uint256 MINT_PHASE1_GHOSTS;
    uint256 MINT_PHASE2_GHOSTS;
    uint256 DEV_AND_COMM_PHASE1_GHOSTS;
    bool PHASE1_ENDED;
    uint256 PUBLIC_PRICE;
    uint256 funds;
    mapping(address => uint256) publicMinted;
}

