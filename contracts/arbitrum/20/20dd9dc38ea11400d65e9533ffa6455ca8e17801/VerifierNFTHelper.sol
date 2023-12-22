// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;
import "./IForeVerifiers.sol";
import "./IERC721Enumerable.sol";

interface IVerifier is IForeVerifiers, IERC721Enumerable {}

contract VerifierNFTHelper {
    IVerifier foreVerifiers;

    struct VerifierNFT {
        uint256 tokenId;
        uint256 multipliedPower;
        uint256 tier;
    }

    constructor(address verifiersAddress) {
        foreVerifiers = IVerifier(verifiersAddress);
    }

    function getVerifiersByOwner(
        address owner
    ) external view returns (VerifierNFT[] memory) {
        uint256 amount = foreVerifiers.balanceOf(owner);

        VerifierNFT[] memory verifierNFTs = new VerifierNFT[](amount);
        for (uint256 i = 0; i < amount; i++) {
            uint256 tokenId = foreVerifiers.tokenOfOwnerByIndex(owner, i);
            uint256 tier = foreVerifiers.nftTier(tokenId);
            uint256 multipliedPower = foreVerifiers.multipliedPowerOf(tokenId);
            verifierNFTs[i] = VerifierNFT(tokenId, multipliedPower, tier);
        }
        return verifierNFTs;
    }
}

