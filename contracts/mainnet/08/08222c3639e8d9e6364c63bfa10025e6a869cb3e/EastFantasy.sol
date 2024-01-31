// SPDX-License-Identifier: MIT
pragma solidity 0.6.6;

import "./ERC721.sol";
import "./Ownable.sol";
import "./SafeMath.sol";

contract EastFantasy is ERC721, Ownable {
    using SafeMath for uint256;
    uint256 public constant MAX_TOKENS = 10000;
    uint256 public Reserve = 10000;

    constructor() public ERC721("EastFantasy", "EF") {

    }

    function withdraw() external onlyOwner {
        msg.sender.transfer(address(this).balance);
    }

    function reserveTokens(address _to, uint256 _reserveAmount) external onlyOwner
    {
        require(
            _reserveAmount > 0 && _reserveAmount <= Reserve,
            "Not enough reserve left for team"
        );
        for (uint256 i = 0; i < _reserveAmount; i++) {
            uint256 id = totalSupply();
            _safeMint(_to, id);
        }
        Reserve = Reserve.sub(_reserveAmount);
    }

    function tokensOfOwner(address _owner) external view returns (uint256[] memory)
    {
        uint256 tokenCount = balanceOf(_owner);
        if (tokenCount == 0) {
            // Return an empty array
            return new uint256[](0);
        } else {
            uint256[] memory result = new uint256[](tokenCount);
            uint256 index;
            for (index = 0; index < tokenCount; index++) {
                result[index] = tokenOfOwnerByIndex(_owner, index);
            }
            return result;
        }
    }

    function setBaseURI(string memory baseURI) public onlyOwner {
        _setBaseURI(baseURI);
    }
}
