//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./ERC721PresetMinterPauserAutoId.sol";
import "./Ownable.sol";

interface iRenderCudl {
    function render(uint256 seed) external view returns (string calldata);
}

contract CudlPets is
    Ownable,
    ERC721PresetMinterPauserAutoId(
        "CUDL Pets",
        "CUDLPets",
        "https://cudl.finance/"
    )
{
    address public game;
    iRenderCudl public metadata;

    function setRender(address _contract) external onlyOwner {
        metadata = iRenderCudl(_contract);
    }

    function setGame(address _game) external onlyOwner {
        game = _game;
    }

    constructor() {}

    function burn(uint256 tokenId) public virtual override {
        //solhint-disable-next-line max-line-length
        require(
            _isApprovedOrOwner(_msgSender(), tokenId) || msg.sender == game,
            "ERC721Burnable: caller is not owner nor approved"
        );
        _burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        return metadata.render(tokenId);
    }
}

