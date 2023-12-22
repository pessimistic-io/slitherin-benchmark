// SPDX-License-Identifier: GPL-2.0-or-later





import "./ISummaSwapV3Manager.sol";
import "./Owned.sol";

contract SummaManagerSnap is Owned{


    ISummaSwapV3Manager public iSummaSwapV3Manager;

    function setISummaSwapV3Manager(ISummaSwapV3Manager _ISummaSwapV3Manager)
        public
        onlyOwner
    {
        iSummaSwapV3Manager = _ISummaSwapV3Manager;
    }
    

    function balanceOf(address owner) public view  returns (uint256) {
        require(owner != address(0), "ERC721: balance query for the zero address");
        return iSummaSwapV3Manager.balanceOf(owner);
    }

    

    /**
     * @dev See {IERC721Enumerable-tokenOfOwnerByIndex}.
     */
    function tokenOfOwnerByIndex(address owner, uint256 index) public view  returns (uint256) {
        return iSummaSwapV3Manager.tokenOfOwnerByIndex(
                owner,
                index
            );
    }

    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        if(tokenId <113){
            return iSummaSwapV3Manager.positions(tokenId);
        }else{
            return (
            0,
            address(0),
            address(0x20f9628a485ebCc566622314f6e07E7Ee61fF332),
            address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1),
            3000,
            0,
            0,
            0,
            0,
            0,
            0,
            0);
        }
    }


     /**
     * @dev See {IERC721-ownerOf}.
     */
    function ownerOf(uint256 tokenId) public view  returns (address) {
        return iSummaSwapV3Manager.ownerOf(tokenId);
    }

}
