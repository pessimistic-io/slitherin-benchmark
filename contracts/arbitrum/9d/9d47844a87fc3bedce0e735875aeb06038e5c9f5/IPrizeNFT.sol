// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./IERC721.sol";
import "./IERC721Enumerable.sol";


interface IPrizeNFT is IERC721, IERC721Enumerable {

    function safeMint(address to) external;
	
}
