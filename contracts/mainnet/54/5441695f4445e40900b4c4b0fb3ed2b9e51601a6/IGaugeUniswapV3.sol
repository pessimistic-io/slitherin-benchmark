// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC721Receiver} from "./ERC721_IERC721Receiver.sol";
import {IGauge} from "./IGauge.sol";

interface IGaugeUniswapV3 is IGauge, IERC721Receiver {
    function earned(uint256 _tokenId) external view returns (uint256);

    function derivedLiquidity(uint128 _liquidity, address account)
        external
        view
        returns (uint256);

    function withdraw(uint256 tokenId) external;

    function getReward(uint256 _tokenId) external;

    function exit(uint256 _tokenId) external;

    function claimFeesMultiple(uint256[] memory _tokenIds) external;

    function claimFees(uint256 _tokenId) external;

    function updateRewardFor(uint256 _tokenId) external;

    function tokenOfOwnerByIndex(address owner, uint256 index)
        external
        view
        returns (uint256);

    function totalNFTSupply() external view returns (uint256);

    function tokenByIndex(uint256 index) external view returns (uint256);

    function isIdsWithinRange(uint256[] memory tokenIds)
        external
        view
        returns (bool[] memory);
}

