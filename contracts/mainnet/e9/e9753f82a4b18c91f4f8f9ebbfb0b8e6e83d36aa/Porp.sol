// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
import "./ERC721A.sol";
import "./PorpRenderer.sol";

contract Porp is ERC721A {
    address private _owner;
    uint256 private _rn;

    mapping(uint256 => bool) public hasporpoise;

    constructor() ERC721A("Porpoise", "PORP") {
        _owner = msg.sender;
    }

    function randomise() public view returns (uint256) {
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        block.difficulty,
                        block.timestamp,
                        block.number,
                        _rn
                    )
                )
            ) % 5;
    }

    function porp(address recipient) public payable {
        uint256 amount = msg.value / 10**16;
        require(amount >= 1, "PAY MORE :)");
        hasporpoise[_nextTokenId()] = randomise() == 0;
        _rn++;
        _mint(recipient, amount);
    }

    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }

    function _beforeTokenTransfers(
        address from,
        address to,
        uint256 startTokenId,
        uint256 quantity
    ) internal virtual override {
        require(msg.value >= 10**16, "ALL XFERS MUST HAVE VALUE");
        (bool success, ) = _owner.call{value: msg.value / 10}("");
        require(success, "YOU MUST PAY :)");
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        if (!_exists(tokenId)) revert URIQueryForNonexistentToken();
        return PorpRenderer.render(hasporpoise[tokenId]);
    }

    function unporp() public {
        address payable to = payable(_owner);
        to.transfer(address(this).balance);
    }
}

