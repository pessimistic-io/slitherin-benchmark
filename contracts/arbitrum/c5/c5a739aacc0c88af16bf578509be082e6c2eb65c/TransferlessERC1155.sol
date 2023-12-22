// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./ERC1155.sol";
import "./IERC20.sol";

contract TransferlessERC1155 is ERC1155 {
    // access control with single gov address, multiple admin addresses
    address public gov;
    mapping(address => bool) public admins;
    // store which tokenids are transferrable
    mapping(uint256 => bool) public transferrable;

    constructor(
        address _gov,
        address[] memory _admins,
        string memory _uri
    ) ERC1155(_uri) {
        gov = _gov;
        for (uint256 i = 0; i < _admins.length; i++) {
            admins[_admins[i]] = true;
        }
    }

    // MODIFIERS:
    modifier onlyGov() {
        require(msg.sender == gov, "Caller is not gov");
        _;
    }
    modifier onlyAdmin() {
        require(admins[msg.sender], "Caller is not an admin");
        _;
    }

    // TOKEN FUNCTIONS:

    function mint(address to, uint256 id, uint256 amount) external onlyAdmin {
        _mint(to, id, amount, "");
    }

    function burn(address from, uint256 id, uint256 amount) external onlyAdmin {
        _burn(from, id, amount);
    }

    //Batch Airdrop Single Token
    function airdropBatchSingle(
        address[] calldata _to,
        uint256 id
    ) external onlyAdmin {
        for (uint256 i = 0; i < _to.length; i++) {
            _mint(_to[i], id, 1, "");
        }
    }

    //Batch Airdrop Multiple Tokens
    function airdropBatchMultiple(
        address[] calldata _to,
        uint256[] calldata ids
    ) external onlyAdmin {
        require(_to.length == ids.length, "addresses and ids length mismatch");
        for (uint256 i = 0; i < _to.length; i++) {
            _mint(_to[i], ids[i], 1, "");
        }
    }

    // override safeTransferFrom and safeBatchTransferFrom functions to prevent user transfers if token is not transferrable
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public virtual override {
        require(transferrable[id], "Token is not transferrable");
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
    ) public virtual override {
        for (uint256 i = 0; i < ids.length; i++) {
            require(transferrable[ids[i]], "Token is not transferrable");
        }
        require(
            from == _msgSender() || isApprovedForAll(from, _msgSender()),
            "ERC1155: caller is not token owner or approved"
        );
        _safeBatchTransferFrom(from, to, ids, amounts, data);
    }

    // PUBLIC VIEW FUNCTIONS:

    // ADMIN FUNCTIONS:

    function setGov(address _gov) external onlyGov {
        gov = _gov;
    }

    function setAdmin(address _admin, bool _isAdmin) external onlyGov {
        admins[_admin] = _isAdmin;
    }

    //change uri
    function setURI(string calldata newuri) external onlyAdmin {
        _setURI(newuri);
    }

    // toggle token transferability
    function setTransferrable(
        uint256 _id,
        bool _transferrable
    ) external onlyAdmin {
        transferrable[_id] = _transferrable;
    }

    function recoverToken(
        address _token,
        address _account,
        uint256 _amount
    ) external onlyGov {
        IERC20(_token).transfer(_account, _amount);
    }
}

