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
     * Mint a GM NFT
     * Only for whitelisted addresses
     * @param merkleProof proof that the address is in whitelist
     */
    function mintGM(bytes32[] memory merkleProof) external {
        require(
            xu3lpa.balanceOf(msg.sender) >= xu3lpBalanceThreshold ||
                xu3lpb.balanceOf(msg.sender) >= xu3lpBalanceThreshold,
                "Not enough balance to mint"
        );
        whitelistedAddresses.verify(msg.sender, merkleProof);
        gm.mint(msg.sender);
    }

    /**
     * Mint a GA NFT
     * Only for whitelisted addresses
     * @param merkleProof proof that the address is in whitelist
     */
    function mintGA(bytes32[] memory merkleProof) external {
        require(
            liquidityPool.updatedBorrowBy(msg.sender) >= debtValueThreshold,
                "Not enough balance to mint"
        );
        whitelistedAddresses.verify(msg.sender, merkleProof);
        ga.mint(msg.sender);
    }

    /**
     * Mint a GN NFT
     * Only for whitelisted addresses
     * @param merkleProof proof that the address is in whitelist
     */
    function mintGN(bytes32[] memory merkleProof) external {
        require(
            xassetLev0.balanceOf(msg.sender) >= levValueThreshold ||
                xassetLev1.balanceOf(msg.sender) >= levValueThreshold,
                "Not enough balance to mint"
        );
        whitelistedAddresses.verify(msg.sender, merkleProof);
        gn.mint(msg.sender);
    }

    /**
     * Claim a free GM/GA/GN NFT
     * Only for first 500 whitelisted addresses
     * NFT to be claimed depends on claim order
     */
    function claimNFT(bytes32[] memory merkleProof) external {
        require(
            claimedCounter <= CLAIMABLE_NFT_LIMIT,
            "No more claimable NFTs"
        );
        require(!claimed[msg.sender], "Address has already claimed his NFT");

        whitelistedAddresses.verify(msg.sender, merkleProof);

        claimed[msg.sender] = true;
        claimedCounter++;

        currentNFT.mint(msg.sender);

        if (currentNFT == gm) {
            currentNFT = ga;
        } else if (currentNFT == ga) {
            currentNFT = gn;
        } else {
            currentNFT = gm;
        }
    }

    // --- Permissioned functions ---

    /**
     * Mint NFTs for owner
     * Limited to 100 NFTs
     */
    function adminMint(IL2NFT nft, uint256 count) external onlyOwner {
        for(uint256 i = 0 ; i < count ; ++i) {
            nft.adminMint(msg.sender);
        }
    }

    /**
     * Set minimum amount of xU3LP tokens
     * for address to be eligible to mint GM NFT
     * @dev _amount is with 18 decimals
     */
    function setXu3lpBalanceThreshold(uint256 _amount) external onlyOwner {
        xu3lpBalanceThreshold = _amount;
    }

    /**
     * Set minimum amount of USDC debt
     * for address to be eligible to mint GA NFT
     * @dev _amount is with 6 decimals
     */
    function setDebtValueThreshold(uint256 _amount) external onlyOwner {
        debtValueThreshold = _amount;
    }

    /**
     * Set minimum amount of xAssetLev tokens
     * for address to be eligible to mint GN NFT
     * @dev _amount is with 18 decimals
     */
    function setLevValueThreshold(uint256 _amount) external onlyOwner {
        levValueThreshold = _amount;
    }
}

