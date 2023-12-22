// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC721.sol";
import "./IERC721Metadata.sol";
import "./Ownable.sol";
import "./Strings.sol";

contract XMetaNFT721 is Ownable, ERC721 {
    using Strings for uint256;

    string private _URI;

    address private proxyRegistryAddress;

    constructor(
        string memory name_,
        string memory symbol_,
        string memory uri_,
        address _proxyRegistryAddress
    ) ERC721(name_, symbol_) {
        _setURI(uri_);
        proxyRegistryAddress = _proxyRegistryAddress;
    }

    /**
     * @dev Throws if called by any account other than the owner or their proxy
     */
    modifier onlyOwnerOrProxy() {
        require(
            _isOwnerOrProxy(_msgSender()),
            "ERC721Tradable#onlyOwner: CALLER_IS_NOT_OWNER"
        );
        _;
    }

    function _setURI(string memory newuri) public virtual {
        require(owner() == _msgSender(), "ONLY_OWNER_ALLOWED");
        _URI = newuri;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _URI;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override(ERC721)
        returns (string memory)
    {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        string memory baseURI = _baseURI();
        return
            bytes(baseURI).length > 0
                ? string(abi.encodePacked(baseURI, tokenId.toString(), ".json"))
                : "";
    }

    function mint(address to, uint256 tokenId) external {
        require(owner() == _msgSender(), "ONLY_OWNER_ALLOWED");
        _mint(to, tokenId);
    }

    // 空投
    function airDrop(address[] memory _to, uint256[] memory _ids) external {
        require(owner() == _msgSender(), "ONLY_OWNER_ALLOWED");
        if (_to.length == 0) {
            revert("Address Lenght Error");
        }
        if (_to.length != _ids.length) {
            revert("tokenId Error");
        }
        uint256 len = _ids.length;
        for (uint256 i = 0; i < len; i++) {
            _mint(_to[i], _ids[i]);
        }
    }

    /*
     * 铸造
     */
    function freeMint(
        address _to,
        uint256[] memory _ids,
        uint256[] memory _amount
    ) external onlyOwnerOrProxy {
        uint256 len = _ids.length;
        uint256 amount_len = _amount.length;
        if (len != amount_len) {
            revert();
        }
        for (uint256 i = 0; i < len; i++) {
            _mint(_to, _ids[i]);
        }
    }

    function _isOwnerOrProxy(address _msgSender) internal view returns (bool) {
        return owner() == _msgSender || _isProxyForUser(_msgSender);
    }

    function _isProxyForUser(address _msgSender)
        internal
        view
        virtual
        returns (bool)
    {
        return proxyRegistryAddress == _msgSender;
    }
}

