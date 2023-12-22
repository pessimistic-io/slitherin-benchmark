// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
import { ISolidStateERC721 } from "./ISolidStateERC721.sol";

interface IWastelands is ISolidStateERC721 {
    // WLLandFacet
    function tokenURI(uint256 tokenId) external view returns (string memory);

    function contractURI() external view returns (string memory);

    //WLMagicRewardsFacet
    function topupMagicRewards(uint256 amount) external;

    function claimMagicReward(uint256 landId) external;

    function claimAllMagicRewards() external;

    function totalClaimable(address account) external view returns (uint256 claimableReward);

    function claimable(uint256 landId) external view returns (uint256);

    function claimed(uint256 landId) external view returns (uint256);

    //WLMintingFacet
    function mintWhitelist(uint256 index, uint256[] calldata tokens, bytes32[] calldata merkleProof) external;

    function hasMintedFromWhitelist(address account) external view returns (bool);
}

