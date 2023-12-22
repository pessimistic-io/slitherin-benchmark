//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./OwnableUpgradeable.sol";
import "./ERC1967UpgradeUpgradeable.sol";

import "./IL2NFT.sol";
import "./ILiquidityPool.sol";
import "./IMerkleTree.sol";

/**
 * Core contract for minting of xToken L2 NFTs
 */
contract ArbitrumNFTCore is OwnableUpgradeable {
    // Mintable NFTs
    IL2NFT public gm;
    IL2NFT public ga;
    IL2NFT public gn;
    // Special NFT
    IL2NFT public wagmi;

    // xToken xU3LPs on L2
    IERC20 private xu3lpa;
    IERC20 private xu3lpb;

    // xToken Lending Liquidity Pool on L2
    ILiquidityPool private liquidityPool;

    // xToken xAssetLev on L2
    IERC20 private xassetLev0;
    IERC20 private xassetLev1;

    IMerkleTree private whitelistedAddresses; // Merkle tree with whitelisted addresses
    IL2NFT private currentNFT; // current free NFT to be claimed by whitelisted addresses
    uint256 public claimedCounter; // Count of addresses which have claimed free NFTs
    mapping(address => bool) public claimed; // map of addresses who have claimed free NFT

    uint256 public xu3lpBalanceThreshold; // xU3LP balance above which user can mint GM NFT
    uint256 public debtValueThreshold; // Lending Loan amount above which user can mint GA NFT
    uint256 public levValueThreshold; // Leveraged assets amount above which user can mint GN NFT

    uint256 private constant CLAIMABLE_NFT_LIMIT = 500; // Count of freely claimable NFTs

    IL2NFT private currentMintableNFT; // current NFT to be claimed by the whitelisted address
    uint256 private mintCounter; // helper counter used for setting currentMintNFT value in a weighted manner
    mapping(address => bool) public roundTwoMinted; // map of addresses who have claimed an NFT in round two

    function initialize(
        IL2NFT _gm,
        IL2NFT _ga,
        IL2NFT _gn,
        IL2NFT _wagmi,
        IERC20 _xu3lpa,
        IERC20 _xu3lpb,
        ILiquidityPool _liquidityPool,
        IERC20 _xassetLev0,
        IERC20 _xassetLev1,
        IMerkleTree _whitelistedAddresses
    ) public initializer {
        __Ownable_init();

        gm = _gm;
        ga = _ga;
        gn = _gn;
        wagmi = _wagmi;
        xu3lpa = _xu3lpa;
        xu3lpb = _xu3lpb;
        liquidityPool = _liquidityPool;
        xassetLev0 = _xassetLev0;
        xassetLev1 = _xassetLev1;
        whitelistedAddresses = _whitelistedAddresses;
        currentNFT = _gm;
        xu3lpBalanceThreshold = 500e18;
        debtValueThreshold = 500e6;
        levValueThreshold = 500e18;
    }
    
    // --- User functions ---
    /**
     * Mint a GM/GA/GN/WAGMI NFT
     * Only for whitelisted addresses
     * @param merkleProof proof that the address is in whitelist
     */
    function mintNFT(bytes32[]memory merkleProof) external {
        require(!roundTwoMinted[msg.sender], "Only addresses that have not previously minted are allowed!");
        whitelistedAddresses.verify(msg.sender, merkleProof);

        roundTwoMinted[msg.sender] = true;
        currentMintableNFT.mint(msg.sender);
        mintCounter++;

        if (mintCounter == 9) {
            currentMintableNFT = wagmi;
            mintCounter = 0;
        } else if (currentMintableNFT == gm) {
            currentMintableNFT = ga;
        } else if (currentMintableNFT == ga) {
            currentMintableNFT = gn;
        } else {
            currentMintableNFT = gm;
        }
    }

    // --- Permissioned functions ---
    function initializeSecondMintStage() external onlyOwner {
        currentMintableNFT = gm;
        mintCounter = 0;
    }

    /**
     * Mint NFTs for owner
     * Limited to 100 NFTs
     */
    function adminMint(IL2NFT nft, uint256 count) external onlyOwner {
        for(uint256 i = 0 ; i < count ; ++i) {
            nft.adminMint(msg.sender);
        }
    }
}

