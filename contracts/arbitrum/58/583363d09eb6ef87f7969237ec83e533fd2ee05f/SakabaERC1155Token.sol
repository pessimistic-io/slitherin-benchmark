// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./ERC1155Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./ERC1155BurnableUpgradeable.sol";
import "./Initializable.sol";
import "./SafeMath.sol";
import "./TokenSignatureVerifier.sol";
import "./ISignerProvider.sol";

contract SakabaERC1155Token is
    Initializable,
    ERC1155Upgradeable,
    OwnableUpgradeable,
    ERC1155BurnableUpgradeable
{
    struct Token {
        uint _tokenId;
        bool _transferable;
    }

    uint[] private _tokenIds;
    mapping(uint => Token) public tokens;
    mapping(address => uint256) public nonces;
    ISignerProvider private provider;

    string public name;
    TokenSignatureVerifier private verifier;

    function __sakabaToken_init(
        string memory _name,
        string memory url,
        ISignerProvider _provider
    ) public initializer {
        verifier = new TokenSignatureVerifier();
        __ERC1155_init(url);
        __Ownable_init();
        __ERC1155Burnable_init();
        provider = _provider;
        name = _name;
    }

    function getTokenIds() public view returns (uint[] memory) {
        return _tokenIds;
    }

    function addTokens(
        uint[] memory tokenIds,
        bool[] memory transferables
    ) public onlyOwner {
        for (uint i = 0; i < tokenIds.length; i++) {
            uint _id = tokenIds[i];
            require(tokens[_id]._tokenId == 0, "token already exists");
            _tokenIds.push(_id);
            Token storage t = tokens[_id];
            t._tokenId = _id;
            t._transferable = transferables[i];
        }
    }

    // to change metadata, only owner can access
    function setURI(string memory newuri) public onlyOwner {
        _setURI(newuri);
    }

    function setTransferable(
        uint tokenId,
        bool transferable
    ) public onlyOwner returns (bool) {
        tokens[tokenId]._transferable = transferable;
        return tokens[tokenId]._transferable;
    }

    function _sakaba_mint(
        address to,
        uint[] memory tokenIds,
        uint[] memory amounts,
        bytes memory signature
    ) public {
        require(
            verifier.verify(
                to,
                address(this),
                block.chainid,
                tokenIds,
                amounts,
                nonces[to],
                provider.getSigner(),
                signature
            ),
            "invalid signature"
        );
        nonces[to] += 1;
        _mintBatch(to, tokenIds, amounts, "");
    }

    function mintBatch(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public onlyOwner {
        _mintBatch(to, ids, amounts, data);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public override {
        require(tokens[id]._transferable == true, "token is non-transferable");
        require(
            from == _msgSender() || isApprovedForAll(from, _msgSender()),
            "ERC1155: caller is not token owner or approved"
        );
        _safeTransferFrom(from, to, id, amount, data);
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public override {
        require(
            from == _msgSender() || isApprovedForAll(from, _msgSender()),
            "caller is not token owner or approved"
        );
        for (uint i = 0; i < ids.length; i++) {
            require(
                tokens[ids[i]]._transferable == true,
                "token is non-transferable"
            );
        }
        _safeBatchTransferFrom(from, to, ids, amounts, data);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(
        address newOwner
    ) public virtual override onlyOwner {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        _transferOwnership(newOwner);
    }
}

